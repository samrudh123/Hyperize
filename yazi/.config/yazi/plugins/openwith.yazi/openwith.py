#!/usr/bin/python3 -I
"""Open-with helper for yazi's Shift+Enter menu (plugins/openwith.yazi).

    openwith.py menu FILE…          JSON for the menu: the apps for FILE's type
    openwith.py launch ID FILE…     open the files with desktop entry ID
    openwith.py forget MIME         drop the remembered apps for MIME
    openwith.py pick FILE…          choose ANY app in the SUPER+D app grid
    openwith.py chosen ID           (internal) the app grid's callback

The menu lists, for the first file's MIME type: the default app, the apps you
picked for that type before (★), then every other installed app that says it
handles the type — the same list GNOME's "Open With" uses (Gio).

`pick` opens the app grid you know from SUPER+D (nwg-drawer, same look, same
search bar, same pinned row) as a picker: clicking an app opens the files
with it and remembers it for that MIME type, so it shows up in the menu from
then on. nwg-drawer can only *launch* things, so the picker instance is shown
a private copy of the app list in which every entry's Exec is
`openwith.py chosen <its id>`; that callback restores the real environment and
launches the real app. The private copy lives in ~/.cache/yazi-openwith —
everything else the drawer reads (icons, themes, categories) is symlinked
through, and its own XDG_DATA_HOME gives it a separate single-instance lock,
so it never toggles a SUPER+D drawer that is already open.

Remembered apps: ~/.local/state/yazi/openwith.json ({mime: [ids…]}).
Nothing is written to mimeapps.list, so xdg-open's defaults never change.
"""
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()
SELF = Path(__file__).resolve()
STATE = Path(os.environ.get("XDG_STATE_HOME") or HOME / ".local/state") / "yazi" / "openwith.json"
CACHE = Path(os.environ.get("XDG_CACHE_HOME") or HOME / ".cache") / "yazi-openwith"
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR") or "/tmp") / "yazi-openwith"
PENDING = RUNTIME / "pending.json"
DRAWER = HOME / ".local/bin/nwg-drawer"
NWG_DATA = HOME / ".local/share/nwg-data"     # category filters (see hypr/app-grid.sh)
TERMINAL = ["ghostty", "--gtk-single-instance=false", "-e"]


def gio():
    import warnings
    import gi
    warnings.simplefilter("ignore")            # PyGIDeprecationWarning chatter
    gi.require_version("Gio", "2.0")
    from gi.repository import Gio
    return Gio


def desktop_app(app_id):
    """The installed desktop entry `app_id`, or None (uninstalled since)."""
    Gio = gio()
    try:
        return Gio.DesktopAppInfo.new(app_id)
    except TypeError:                          # "constructor returned NULL"
        return None


# ── remembered apps ─────────────────────────────────────────────────────────

def load_state():
    try:
        return json.loads(STATE.read_text())
    except (OSError, ValueError):
        return {}


def remember(mime, app_id):
    st = load_state()
    ids = [i for i in st.get(mime, []) if i != app_id]
    st[mime] = [app_id] + ids
    STATE.parent.mkdir(parents=True, exist_ok=True)
    tmp = STATE.with_suffix(".tmp")
    tmp.write_text(json.dumps(st, indent=1, sort_keys=True))
    os.replace(tmp, STATE)


def forget(mime):
    st = load_state()
    if st.pop(mime, None) is not None:
        STATE.write_text(json.dumps(st, indent=1, sort_keys=True))


# ── types and apps ──────────────────────────────────────────────────────────

def mime_of(path):
    Gio = gio()
    try:
        info = Gio.File.new_for_path(path).query_info("standard::content-type", 0, None)
        return info.get_content_type() or "application/octet-stream"
    except Exception:
        return "application/octet-stream"


def menu(files):
    Gio = gio()
    mime = mime_of(files[0])
    default = Gio.AppInfo.get_default_for_type(mime, False)
    remembered = [desktop_app(i) for i in load_state().get(mime, [])]
    rows, seen_ids, seen_names = [], set(), set()

    def add(app, tag):
        if not app or app.get_id() in seen_ids:
            return
        name = app.get_display_name() or app.get_name() or app.get_id()
        # the same app installed twice (deb + flatpak/snap) shows once
        if tag == "" and name in seen_names:
            return
        seen_ids.add(app.get_id())
        seen_names.add(name)
        rows.append({"id": app.get_id(), "name": name, "tag": tag})

    add(default, "default")
    for app in remembered:
        add(app, "remembered")
    for app in Gio.AppInfo.get_all_for_type(mime):
        add(app, "")
    desc = Gio.content_type_get_description(mime) or mime
    print(json.dumps({"mime": mime, "desc": desc, "apps": rows,
                      "remembered": bool(load_state().get(mime))}))


def command_for(app, files):
    """argv list(s) for desktop entry `app` opening `files` (Desktop Entry spec
    field codes; %f / %u with several files = one process per file)."""
    exec_ = app.get_string("Exec") or ""
    try:
        tokens = shlex.split(exec_)
    except ValueError:
        tokens = exec_.split()
    has_code = any(c in exec_ for c in ("%f", "%F", "%u", "%U"))
    single = ("%f" in exec_ or "%u" in exec_) and not ("%F" in exec_ or "%U" in exec_)
    batches = [[f] for f in files] if single else [files]

    out = []
    for batch in batches:
        b_uris = [Path(f).absolute().as_uri() for f in batch]
        argv = []
        for t in tokens:
            if t in ("@@", "@@u", "@@f"):          # flatpak file-forwarding markers
                continue
            if t in ("%F", "%f"):
                argv += batch
            elif t in ("%U", "%u"):
                argv += b_uris
            elif t == "%i":
                icon = app.get_string("Icon")
                argv += ["--icon", icon] if icon else []
            elif t in ("%d", "%D", "%n", "%N", "%v", "%m"):
                continue
            else:
                # codes inside a word (--file=%f); unknown ones are dropped
                t = re.sub(r"%(.)", lambda m: {
                    "%": "%", "c": app.get_name() or "", "k": app.get_filename() or "",
                    "f": batch[0], "u": b_uris[0]}.get(m.group(1), ""), t)
                argv.append(t)
        if not has_code:
            argv += batch
        if app.get_boolean("Terminal"):
            argv = TERMINAL + argv
        out.append(argv)
    return out


def launch(app_id, files):
    app = desktop_app(app_id)
    if not app:
        sys.exit(f"no such app: {app_id}")
    cwd = str(Path(files[0]).absolute().parent) if files else str(HOME)
    for argv in command_for(app, files):
        subprocess.Popen(argv, cwd=cwd, start_new_session=True, stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


# ── the app grid as a picker ────────────────────────────────────────────────

def mirror(src, dst, skip):
    """dst/ = symlinks to everything in src/ except `skip`."""
    dst.mkdir(parents=True, exist_ok=True)
    try:
        entries = os.listdir(src)
    except OSError:
        return
    for name in entries:
        if name not in skip:
            os.symlink(os.path.join(src, name), dst / name)


def desktop_escape(s):
    return (s or "").replace("\\", "\\\\").replace("\n", "\\n")


def build_drawer_env():
    Gio = gio()
    real_home = os.environ.get("XDG_DATA_HOME") or str(HOME / ".local/share")
    real_dirs = [d for d in (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share/:/usr/share/").split(":") if d]

    shutil.rmtree(CACHE, ignore_errors=True)
    home = CACHE / "home"
    mirror(real_home, home, {"applications", "nwg-drawer"})
    apps = home / "applications"
    apps.mkdir()
    sys_dirs = []
    for i, d in enumerate(real_dirs):
        if Path(d).resolve() == NWG_DATA.resolve():
            continue
        dst = CACHE / f"sys{i}"
        mirror(d, dst, {"applications", "nwg-drawer"})
        sys_dirs.append(str(dst))

    for app in Gio.AppInfo.get_all():
        if not app.should_show() or not hasattr(app, "get_categories"):
            continue
        icon = app.get_icon()
        lines = [
            "[Desktop Entry]",
            "Type=Application",
            f"Name={desktop_escape(app.get_name())}",
            f"Exec=/usr/bin/python3 {SELF} chosen {app.get_id()}",
            "Terminal=false",
        ]
        for key, val in (("GenericName", app.get_generic_name()),
                         ("Comment", app.get_description()),
                         ("Icon", icon.to_string() if icon else None),
                         ("Categories", app.get_categories()),
                         ("Keywords", ";".join(app.get_keywords() or []) or None)):
            if val:
                lines.append(f"{key}={desktop_escape(val)}")
        (apps / app.get_id()).write_text("\n".join(lines) + "\n")

    env = dict(os.environ)
    env["XDG_DATA_HOME"] = str(home)
    env["XDG_DATA_DIRS"] = ":".join([str(NWG_DATA)] + sys_dirs)
    return env


def pick(files):
    mime = mime_of(files[0])
    RUNTIME.mkdir(parents=True, exist_ok=True)
    PENDING.write_text(json.dumps({
        "files": [str(Path(f).absolute()) for f in files],
        "mime": mime,
        "time": time.time(),
        # what the callback has to restore before launching the real app
        "env": {k: os.environ.get(k) for k in ("XDG_DATA_HOME", "XDG_DATA_DIRS")},
    }))
    env = build_drawer_env()
    # same look as SUPER+D (hypr/app-grid.sh); file search off — it would
    # open files, not pick an app
    subprocess.Popen([str(DRAWER), "-c", "7", "-is", "56", "-nofs", "-ovl"], env=env,
                     start_new_session=True, stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def chosen(app_id):
    try:
        p = json.loads(PENDING.read_text())
    except (OSError, ValueError):
        return
    PENDING.unlink(missing_ok=True)
    if time.time() - p.get("time", 0) > 3600:
        return
    for k, v in p.get("env", {}).items():
        if v is None:
            os.environ.pop(k, None)
        else:
            os.environ[k] = v
    launch(app_id, p["files"])
    remember(p["mime"], app_id)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == "chosen" and args:
        chosen(args[0])          # before anything imports Gio with the fake env
    elif cmd == "menu" and args:
        menu(args)
    elif cmd == "launch" and len(args) >= 2:
        launch(args[0], args[1:])
    elif cmd == "forget" and args:
        forget(args[0])
    elif cmd == "pick" and args:
        pick(args)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
