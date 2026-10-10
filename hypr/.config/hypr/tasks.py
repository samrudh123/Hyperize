#!/usr/bin/python3
"""Tasks — the bottom bar's to-do icon, its panel, and the daily log.

    tasks.py status          waybar JSON for custom/tasks (count + tooltip)
    tasks.py toggle          open the panel, or close it if it is open
    tasks.py panel           open the panel
    tasks.py quickadd        one-line fuzzel prompt -> new task (right-click)
    tasks.py add TEXT        add a task from a terminal
    tasks.py log TEXT        add a timestamped line to today's log
    tasks.py list            print remaining + done today
    tasks.py checkin [morning|midday|evening]
                             the scheduled nudge (tasks-checkin.timer); with no
                             argument the kind is picked from the clock

THE FILES ARE THE DATABASE

  ~/notes/tasks.md               every open task, plus the ones finished today
  ~/notes/daily/YYYY-MM-DD.md    one per day: Done, Still open, Log

Plain markdown on purpose, so they stay readable and greppable long after
this panel is gone, and editing them in an editor is fine: tasks.md is one
"- [ ] text" line per task (tick with [x]); the trailing <!-- --> comment holds
the dates and is invisible in any markdown viewer. Lines that are not tasks
are not kept.

In a day file, "Done" and "Still open" are regenerated from tasks.md whenever
today changes, so hand edits there do not survive; "Log" is yours and is only
ever appended to (or edited from the panel).

ROLLOVER
The first time anything runs on a new day, i.e. the bar's poll a few seconds
after midnight, tasks finished on an earlier day are merged into that day's
file and dropped from tasks.md. Open tasks just stay and show how long they
have been carried.

Normal toplevel window, like network-panel.py and for the same reasons; the
windowrules in hyprland.conf match the app_id set by GLib.set_prgname().
"""

import datetime as dt
import html
import json
import os
import re
import subprocess
import sys
import tempfile

NOTES = os.path.expanduser(os.environ.get("TASKS_NOTES_DIR", "~/notes"))  # override for testing
TASKS_FILE = os.path.join(NOTES, "tasks.md")
DAILY_DIR = os.path.join(NOTES, "daily")
ACCENT_FILE = os.path.expanduser("~/.config/hypr/theme/accent")
SELF = os.path.abspath(__file__)

TASKS_HEADER = """\
# Tasks
<!-- Managed by ~/.config/hypr/tasks.py. Hand edits are fine: one "- [ ] text"
     line per task, [x] to tick. Lines that are not tasks are not kept. -->
"""

TASK_RE = re.compile(r"^\s*[-*] \[([ xX])\]\s+(.*?)\s*(?:<!--(.*?)-->)?\s*$")
DATE_RE = re.compile(r"\d{4}-\d{2}-\d{2}")
GLYPH_OPEN, GLYPH_CLEAR = "\U000f0131", "\U000f0132"  # md-checkbox_blank_outline / _marked



def _rice_subst(css):
    """Desktop THEMES (SUPER+T): this CSS is written in Catppuccin Mocha;
    recolour it into the current theme (rice-theme.py palette substitution)."""
    try:
        import importlib.util
        import os as _os
        spec = importlib.util.spec_from_file_location(
            "rice_theme", _os.path.expanduser("~/.config/hypr/rice-theme.py"))
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod.subst(css, mod.current())
    except Exception:              # noqa: BLE001 — fall back to Mocha
        return css

def now():
    return dt.datetime.now()


def today():
    return now().strftime("%Y-%m-%d")


class Task:
    __slots__ = ("text", "done_at", "added")

    def __init__(self, text, done_at="", added=""):
        self.text = text
        self.done_at = done_at  # "YYYY-MM-DD HH:MM" when done, else ""
        self.added = added      # "YYYY-MM-DD", or "" for hand-written lines

    @property
    def done(self):
        return bool(self.done_at)

    @property
    def done_day(self):
        return self.done_at[:10]

    def copy(self):
        return Task(self.text, self.done_at, self.added)

    def line(self):
        meta = []
        if self.added:
            meta.append(f"added {self.added}")
        if self.done_at:
            meta.append(f"done {self.done_at}")
        tail = f" <!-- {'; '.join(meta)} -->" if meta else ""
        return f"- [{'x' if self.done else ' '}] {self.text}{tail}"

    def age_days(self):
        if not self.added:
            return 0
        try:
            return (now().date() - dt.date.fromisoformat(self.added)).days
        except ValueError:
            return 0


# ── storage ─────────────────────────────────────────────────────────────────

def atomic_write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".tmp-")
    with os.fdopen(fd, "w") as fh:
        fh.write(text)
    os.replace(tmp, path)


def read_text(path):
    try:
        with open(path) as fh:
            return fh.read()
    except OSError:
        return ""


def parse_tasks(text):
    tasks, stamp = [], False
    for raw in text.splitlines():
        m = TASK_RE.match(raw)
        if not m or not m.group(2):
            continue
        added = done_at = ""
        for part in (m.group(3) or "").split(";"):
            part = part.strip()
            if part.startswith("added "):
                added = part[6:].strip()
            elif part.startswith("done "):
                done_at = part[5:].strip()
        if m.group(1) in "xX" and not done_at:
            # Ticked by hand in an editor: count it as done now.
            done_at, stamp = now().strftime("%Y-%m-%d %H:%M"), True
        if m.group(1) == " ":
            done_at = ""  # unticked by hand
        tasks.append(Task(m.group(2), done_at, added))
    return tasks, stamp


def render_tasks(tasks):
    open_ = [t.line() for t in tasks if not t.done]
    done = [t.line() for t in tasks if t.done]
    return TASKS_HEADER + "\n" + "\n".join(open_ + done) + ("\n" if tasks else "")


def save_tasks(tasks):
    text = render_tasks(tasks)
    atomic_write(TASKS_FILE, text)
    return text


def day_path(day):
    return os.path.join(DAILY_DIR, f"{day}.md")


def read_day(day):
    sections = {"done": [], "open": [], "log": []}
    current = None
    for raw in read_text(day_path(day)).splitlines():
        if raw.startswith("## "):
            head = raw[3:].lower()
            current = ("done" if head.startswith("done") else
                       "open" if head.startswith("still open") else
                       "log" if head.startswith("log") else None)
        elif current and raw.startswith("- "):
            sections[current].append(raw)
    return sections


def write_day(day, sections):
    title = dt.date.fromisoformat(day).strftime("%A, %-d %B %Y")
    out = [f"# {title}", ""]
    for key, head in (("done", "Done"), ("open", "Still open"), ("log", "Log")):
        items = sections[key]
        out.append(f"## {head} ({len(items)})" if key != "log" else "## Log")
        if items:
            out.extend(items)
        elif key != "log":
            out.append("_nothing_")
        out.append("")
    atomic_write(day_path(day), "\n".join(out))


def done_line(t):
    return f"- [x] {t.text} · {t.done_at[11:16]}"


def sync_day(tasks, day=None):
    """Regenerate today's Done / Still open from tasks.md, keeping the Log."""
    day = day or today()
    sec = read_day(day)
    done = [done_line(t) for t in tasks if t.done and t.done_day == day]
    if not (done or sec["log"] or os.path.exists(day_path(day))):
        return  # nothing happened today yet; no empty files
    sec["done"] = done
    sec["open"] = [f"- [ ] {t.text}" for t in tasks if not t.done]
    write_day(day, sec)


def rollover(tasks):
    """Archive tasks finished before today into their day files."""
    day = today()
    stale = [t for t in tasks if t.done and t.done_day < day]
    if not stale:
        return tasks, False
    for d in sorted({t.done_day for t in stale}):
        if not DATE_RE.fullmatch(d):
            continue
        sec = read_day(d)
        for line in (done_line(t) for t in stale if t.done_day == d):
            if line not in sec["done"]:
                sec["done"].append(line)
        write_day(d, sec)
    return [t for t in tasks if t not in stale], True


def load():
    """tasks.md parsed, rolled over, and re-saved if either changed anything."""
    tasks, stamp = parse_tasks(read_text(TASKS_FILE))
    tasks, rolled = rollover(tasks)
    if stamp or rolled:
        save_tasks(tasks)
        sync_day(tasks)
    return tasks


def commit(tasks):
    text = save_tasks(tasks)
    sync_day(tasks)
    return text


def add_log(text):
    day = today()
    sec = read_day(day)
    sec["log"].append(f"- {now().strftime('%H:%M')} {text}")
    tasks, _ = parse_tasks(read_text(TASKS_FILE))
    sec["done"] = [done_line(t) for t in tasks if t.done and t.done_day == day]
    sec["open"] = [f"- [ ] {t.text}" for t in tasks if not t.done]
    write_day(day, sec)


def split_log(line):
    """'- 14:05 text' -> ('14:05', 'text')."""
    m = re.match(r"^- (\d{1,2}:\d{2})\s+(.*)$", line)
    return (m.group(1), m.group(2)) if m else ("", line[2:])


def split_buckets(tasks):
    day = today()
    return ([t for t in tasks if not t.done],
            [t for t in tasks if t.done and t.done_day == day])


# ── bar / CLI ───────────────────────────────────────────────────────────────

def cmd_status():
    try:
        tasks = load()
    except Exception as exc:  # never break the bar
        print(json.dumps({"text": GLYPH_OPEN + " !", "tooltip": str(exc), "class": "error"}, ensure_ascii=False))
        return
    pending, done = split_buckets(tasks)
    esc = html.escape
    lines = []
    if pending:
        lines.append(f"<b>Remaining ({len(pending)})</b>")
        lines += [f"  ○  {esc(t.text)}" for t in pending[:12]]
        if len(pending) > 12:
            lines.append(f"  … {len(pending) - 12} more")
    if done:
        lines.append(f"<b>Done today ({len(done)})</b>")
        lines += [f"  ✓  {esc(t.text)}" for t in done[:8]]
        if len(done) > 8:
            lines.append(f"  … {len(done) - 8} more")
    if not lines:
        lines.append("No tasks yet")
    lines.append("\nClick: open tasks · Right-click: quick add")
    if pending:
        text, cls = f"{GLYPH_OPEN}  {len(pending)}", "pending"
    else:
        text, cls = GLYPH_CLEAR, ("clear" if done else "empty")
    print(json.dumps({"text": text, "tooltip": "\n".join(lines), "class": cls}, ensure_ascii=False))


def panel_pids():
    out = subprocess.run(["pgrep", "-f", f"{SELF} panel"], capture_output=True, text=True)
    return [int(p) for p in out.stdout.split() if int(p) != os.getpid()]


def cmd_toggle():
    pids = panel_pids()
    if pids:
        for pid in pids:
            os.kill(pid, 15)
        return
    os.execv(sys.executable, [sys.executable, SELF, "panel"])


def cmd_quickadd():
    out = subprocess.run(["fuzzel", "--dmenu", "--prompt-only", "New task: "],
                         capture_output=True, text=True)
    text = out.stdout.strip()
    if out.returncode == 0 and text:
        cmd_add(text)


def cmd_add(text):
    text = " ".join(text.split())
    if not text:
        return
    tasks = load()
    tasks.append(Task(text, added=today()))
    commit(tasks)


def cmd_list():
    pending, done = split_buckets(load())
    print(f"Remaining ({len(pending)})")
    for t in pending:
        age = t.age_days()
        print(f"  [ ] {t.text}" + (f"   ({age}d)" if age else ""))
    print(f"Done today ({len(done)})")
    for t in done:
        print(f"  [x] {t.text}   {t.done_at[11:16]}")


def cmd_checkin(kind=None):
    tasks = load()
    sync_day(tasks)
    pending, done = split_buckets(tasks)
    hour = now().hour
    kind = kind or ("morning" if hour < 12 else "midday" if hour < 18 else "evening")

    def bullets(items, mark, limit=6):
        rows = [f"{mark} {t.text}" for t in items[:limit]]
        if len(items) > limit:
            rows.append(f"… and {len(items) - limit} more")
        return "\n".join(rows)

    if kind == "morning":
        title = (f"Good morning: {len(pending)} task{'s' if len(pending) != 1 else ''} on deck"
                 if pending else "Good morning: your list is empty")
        body = bullets(pending, "○") if pending else "Add today's tasks from the bottom bar."
    elif kind == "midday":
        title = f"Check-in: {len(done)} done, {len(pending)} to go"
        body = "What have you done so far? Log it in the panel."
        if pending:
            body += "\n\n" + bullets(pending, "○", 4)
    else:
        title = f"Day wrap-up: {len(done)} done, {len(pending)} carried over"
        body = (bullets(done, "✓") if done else "Nothing ticked off today.") + \
            f"\n\nSaved to ~/notes/daily/{today()}.md"

    if notify(title, body) == "default" and not panel_pids():
        # Through Hyprland, not Popen: a child of this oneshot service would
        # be killed with the service's cgroup the moment this returns.
        subprocess.run(["hyprctl", "dispatch", "exec", f"{sys.executable} {SELF} panel"],
                       capture_output=True)


def notify(title, body, timeout_ms=20000):
    """Show a notification and wait for it; returns the invoked action, if any.

    Straight over D-Bus rather than `notify-send -A`: libnotify 0.8.8's
    notify-send refuses actions here ("Actions are not supported by this
    notifications server") even though mako advertises them. "default" is
    the action mako runs on a left-click on the notification itself.
    """
    from gi.repository import Gio, GLib

    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    except GLib.Error:
        return None
    loop, state = GLib.MainLoop(), {}

    def on_signal(_conn, _sender, _path, _iface, signal, params):
        if params[0] != state.get("id"):
            return
        if signal == "ActionInvoked":
            state["action"] = params[1]
        loop.quit()

    bus.signal_subscribe(None, "org.freedesktop.Notifications", None,
                         "/org/freedesktop/Notifications", None,
                         Gio.DBusSignalFlags.NONE, on_signal)
    try:
        reply = bus.call_sync(
            "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
            "org.freedesktop.Notifications", "Notify",
            GLib.Variant("(susssasa{sv}i)", (
                "Tasks", 0, "gnome-todo", title, html.escape(body, quote=False),
                ["default", "Open tasks"], {}, timeout_ms)),
            GLib.VariantType("(u)"), Gio.DBusCallFlags.NONE, -1, None)
    except GLib.Error:
        return None  # no notification daemon running
    state["id"] = reply.unpack()[0]
    GLib.timeout_add(timeout_ms + 5000, loop.quit)
    loop.run()
    return state.get("action")


# ── panel ───────────────────────────────────────────────────────────────────

def read_accent():
    try:
        hexval = read_text(ACCENT_FILE).strip().lstrip("#")
        if re.fullmatch(r"[0-9a-fA-F]{6}", hexval):
            return "#" + hexval
    except OSError:
        pass
    return "#89b4fa"


def run_panel():
    import gi

    gi.require_version("Gtk", "3.0")
    gi.require_version("Gdk", "3.0")  # pinned before import: see network-panel.py
    from gi.repository import GLib

    GLib.set_prgname("tasks-panel")  # app_id, before Gtk/Gdk are imported
    from gi.repository import Gdk, Gio, Gtk, Pango

    accent = read_accent()
    BASE, MANTLE, SURFACE0, SURFACE1 = "#1e1e2e", "#181825", "#313244", "#45475a"
    TEXT, SUBTEXT, OVERLAY = "#cdd6f4", "#a6adc8", "#6c7086"
    GREEN, RED, PEACH = "#a6e3a1", "#f38ba8", "#fab387"

    css = f"""
    window, .panel {{ background: {BASE}; color: {TEXT}; }}
    notebook header {{ background: {MANTLE}; border: none; }}
    notebook header tab {{
        color: {OVERLAY}; padding: 8px 18px; border: none;
        background: transparent; font-weight: 600;
    }}
    notebook header tab:checked {{ color: {accent}; box-shadow: inset 0 -2px 0 {accent}; }}
    notebook > stack {{ background: {BASE}; }}
    list, row {{ background: transparent; }}
    row {{ padding: 1px 4px; border-bottom: 1px solid {MANTLE}; }}
    row:hover {{ background: alpha({SURFACE0}, 0.5); }}
    row:selected {{ background: transparent; }}
    .section {{ color: {accent}; font-size: 8.5pt; font-weight: 700; padding: 12px 10px 4px; }}
    .section-done {{ color: {GREEN}; }}
    .section-log {{ color: {PEACH}; }}
    .task {{ font-size: 10.5pt; color: {TEXT}; }}
    .task-done {{ color: {OVERLAY}; text-decoration-line: line-through; }}
    .meta {{ font-size: 8.5pt; color: {OVERLAY}; }}
    .meta-old {{ color: {PEACH}; }}
    .empty {{ color: {OVERLAY}; font-style: italic; font-size: 9pt; padding: 6px 12px; }}
    .status {{ font-size: 9pt; color: {SUBTEXT}; padding: 6px 10px; background: {MANTLE}; }}
    .toolbar {{ background: {MANTLE}; padding: 8px; }}
    button {{
        background: {SURFACE0}; color: {TEXT}; border: none; box-shadow: none;
        border-radius: 6px; padding: 5px 12px; font-size: 9pt;
    }}
    button:hover {{ background: {SURFACE1}; }}
    button.suggested-action {{ background: {accent}; color: {BASE}; font-weight: 700; }}
    button.icon {{
        background: transparent; color: {OVERLAY}; padding: 2px 6px;
        min-width: 0; min-height: 0; font-size: 11pt;
        font-family: "JetBrainsMono Nerd Font";
    }}
    button.icon:hover {{ background: {SURFACE0}; color: {TEXT}; }}
    button.icon.danger:hover {{ color: {RED}; }}
    entry {{
        background: {SURFACE0}; color: {TEXT}; border: none; box-shadow: none;
        border-radius: 6px; padding: 7px 10px;
    }}
    entry:focus {{ box-shadow: inset 0 0 0 2px {accent}; }}
    entry.inline {{ padding: 3px 8px; }}
    check {{
        background: {SURFACE0}; border: 1px solid {SURFACE1}; border-radius: 5px;
        min-width: 16px; min-height: 16px; -gtk-icon-source: none; box-shadow: none;
    }}
    check:checked {{
        background: {GREEN}; border-color: {GREEN};
        -gtk-icon-source: -gtk-icontheme("object-select-symbolic"); color: {BASE};
    }}
    combobox button {{ padding: 5px 10px; }}
    .history {{ padding: 14px 18px; }}
    """

    ICON_UP, ICON_DOWN = "\U000f005d", "\U000f0045"     # md-arrow_up / _down
    ICON_EDIT, ICON_DEL = "\U000f03eb", "\U000f01b4"    # md-pencil / md-delete

    def icon_button(glyph, tip, cb, danger=False):
        b = Gtk.Button(label=glyph)
        b.set_tooltip_text(tip)
        b.set_relief(Gtk.ReliefStyle.NONE)
        b.set_can_focus(False)
        ctx = b.get_style_context()
        ctx.add_class("icon")
        if danger:
            ctx.add_class("danger")
        b.connect("clicked", lambda _b: cb())
        return b

    def section_label(text, extra=None):
        lbl = Gtk.Label(label=text, xalign=0)
        lbl.get_style_context().add_class("section")
        if extra:
            lbl.get_style_context().add_class(extra)
        return lbl

    class EditableRow(Gtk.ListBoxRow):
        """A row whose text turns into an entry on double-click or the pencil."""

        def __init__(self, panel, text, on_save, label_classes=("task",)):
            super().__init__()
            self.panel, self.on_save, self.text = panel, on_save, text
            self.set_activatable(False)
            self.set_selectable(False)
            self.box = Gtk.Box(spacing=6, margin_start=6, margin_end=4,
                               margin_top=3, margin_bottom=3)
            self.add(self.box)

            self.stack = Gtk.Stack()
            self.stack.set_hhomogeneous(False)
            self.label = Gtk.Label(label=text, xalign=0)
            self.label.set_line_wrap(True)
            self.label.set_line_wrap_mode(Pango.WrapMode.WORD_CHAR)
            for cls in label_classes:
                self.label.get_style_context().add_class(cls)
            ebox = Gtk.EventBox()
            ebox.add(self.label)
            ebox.connect("button-press-event", self._on_click)
            self.stack.add_named(ebox, "view")

            self.entry = Gtk.Entry()
            self.entry.get_style_context().add_class("inline")
            self.entry.connect("activate", lambda _e: self.finish(True))
            self.entry.connect("key-press-event", self._on_entry_key)
            self.entry.connect("focus-out-event", lambda *_: self.finish(True) and False)
            self.stack.add_named(self.entry, "edit")
            self.editing = False

        def pack_text(self):
            self.box.pack_start(self.stack, True, True, 0)

        def _on_click(self, _w, event):
            if event.type == Gdk.EventType.DOUBLE_BUTTON_PRESS:
                self.start_edit()
            return False

        def _on_entry_key(self, _w, event):
            if event.keyval == Gdk.KEY_Escape:
                self.finish(False)
                return True
            return False

        def start_edit(self):
            if self.editing:
                return
            self.editing = True
            self.panel.editing = self
            self.entry.set_text(self.text)
            self.stack.set_visible_child_name("edit")
            self.entry.grab_focus()
            self.entry.select_region(0, -1)

        def finish(self, save):
            if not self.editing:
                return False
            self.editing = False
            if self.panel.editing is self:
                self.panel.editing = None
            new = " ".join(self.entry.get_text().split())
            self.stack.set_visible_child_name("view")
            if save and new and new != self.text:
                # Deferred: saving rebuilds the list, which would destroy this
                # entry inside its own signal handler.
                GLib.idle_add(lambda: self.on_save(new) and False)
            return False

    class TasksPanel(Gtk.Window):
        def __init__(self):
            super().__init__(title="Tasks")
            self.set_default_size(440, 620)
            self.get_style_context().add_class("panel")
            self.editing = None
            self.undo = []
            self.last_written = None
            self.day = today()

            outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            self.add(outer)
            self.notebook = Gtk.Notebook()
            outer.pack_start(self.notebook, True, True, 0)
            self.notebook.append_page(self._build_today(), Gtk.Label(label="Today"))
            self.notebook.append_page(self._build_history(), Gtk.Label(label="History"))
            self.notebook.connect("switch-page", self._on_switch)

            self.status = Gtk.Label(xalign=0, label="")
            self.status.get_style_context().add_class("status")
            self.status.set_ellipsize(Pango.EllipsizeMode.END)
            outer.pack_end(self.status, False, False, 0)

            self.connect("key-press-event", self.on_key)
            self.connect("destroy", Gtk.main_quit)

            # Hand edits and `tasks.py add` from a terminal show up live.
            self.monitors = []
            for path in (TASKS_FILE, day_path(self.day)):
                mon = Gio.File.new_for_path(path).monitor_file(Gio.FileMonitorFlags.NONE, None)
                mon.connect("changed", self._on_file_changed)
                self.monitors.append(mon)
            # Midnight while open: roll over without needing a restart.
            GLib.timeout_add_seconds(30, self._tick)

            self.reload()
            self.say_counts()

        # ── layout ──
        def _build_today(self):
            page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)

            bar = Gtk.Box(spacing=6)
            bar.get_style_context().add_class("toolbar")
            self.add_entry = Gtk.Entry(placeholder_text="Add a task…  (Enter)")
            self.add_entry.connect("activate", lambda _e: self.on_add())
            bar.pack_start(self.add_entry, True, True, 0)
            add = Gtk.Button(label="Add")
            add.get_style_context().add_class("suggested-action")
            add.connect("clicked", lambda _b: self.on_add())
            bar.pack_start(add, False, False, 0)
            page.pack_start(bar, False, False, 0)

            scroll = Gtk.ScrolledWindow()
            scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
            self.body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            scroll.add(self.body)
            page.pack_start(scroll, True, True, 0)

            logbar = Gtk.Box(spacing=6)
            logbar.get_style_context().add_class("toolbar")
            self.log_entry = Gtk.Entry(placeholder_text="Log an update…  e.g. finished the report draft")
            self.log_entry.connect("activate", lambda _e: self.on_log())
            logbar.pack_start(self.log_entry, True, True, 0)
            logb = Gtk.Button(label="Log")
            logb.connect("clicked", lambda _b: self.on_log())
            logbar.pack_start(logb, False, False, 0)
            page.pack_start(logbar, False, False, 0)
            return page

        def _build_history(self):
            page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            bar = Gtk.Box(spacing=6)
            bar.get_style_context().add_class("toolbar")
            self.day_combo = Gtk.ComboBoxText()
            self.day_combo.connect("changed", lambda _c: self.show_day())
            bar.pack_start(self.day_combo, True, True, 0)
            opener = Gtk.Button(label="Open file")
            opener.set_tooltip_text("Open this day's markdown file")
            opener.connect("clicked", lambda _b: self.open_day_file())
            bar.pack_start(opener, False, False, 0)
            page.pack_start(bar, False, False, 0)

            scroll = Gtk.ScrolledWindow()
            scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
            self.history = Gtk.Label(xalign=0, yalign=0)
            self.history.set_line_wrap(True)
            self.history.set_selectable(True)
            self.history.get_style_context().add_class("history")
            scroll.add(self.history)
            page.pack_start(scroll, True, True, 0)
            return page

        # ── data ──
        def reload(self):
            self.tasks = load()
            self.last_written = read_text(TASKS_FILE)
            self.log = read_day(today())["log"]
            self.render()

        def snapshot(self):
            self.undo.append(([t.copy() for t in self.tasks], list(self.log)))
            del self.undo[:-30]

        def save(self, message=None):
            self.last_written = commit(self.tasks)
            sec = read_day(today())
            if sec["log"] != self.log:
                sec["log"] = self.log
                if self.log or os.path.exists(day_path(today())):
                    write_day(today(), sec)
            self.render()
            if message:
                self.say(message)
            else:
                self.say_counts()

        # ── actions ──
        def on_add(self):
            text = " ".join(self.add_entry.get_text().split())
            if not text:
                return
            self.snapshot()
            self.tasks.append(Task(text, added=today()))
            self.add_entry.set_text("")
            self.save(f"Added “{text}”")

        def on_log(self):
            text = " ".join(self.log_entry.get_text().split())
            if not text:
                return
            self.snapshot()
            self.log.append(f"- {now().strftime('%H:%M')} {text}")
            self.log_entry.set_text("")
            self.save("Logged to today's file")

        def set_done(self, task, done):
            if task.done == done:
                return
            self.snapshot()
            task.done_at = now().strftime("%Y-%m-%d %H:%M") if done else ""
            # A ticked task goes to the end so the done list reads in order.
            self.tasks.remove(task)
            self.tasks.append(task)
            GLib.idle_add(lambda: self.save(f"Done: “{task.text}”" if done else
                                            f"Back on the list: “{task.text}”") and False)

        def rename(self, task, text):
            self.snapshot()
            task.text = text
            self.save("Edited")

        def delete(self, task):
            self.snapshot()
            self.tasks.remove(task)
            self.save(f"Deleted “{task.text}”  ·  Ctrl+Z to undo")

        def move(self, task, step):
            pending = [t for t in self.tasks if not t.done]
            i = pending.index(task)
            j = i + step
            if not 0 <= j < len(pending):
                return
            self.snapshot()
            a, b = self.tasks.index(pending[i]), self.tasks.index(pending[j])
            self.tasks[a], self.tasks[b] = self.tasks[b], self.tasks[a]
            self.save()

        def edit_log(self, index, text):
            self.snapshot()
            stamp, _ = split_log(self.log[index])
            self.log[index] = f"- {stamp} {text}" if stamp else f"- {text}"
            self.save("Edited log entry")

        def delete_log(self, index):
            self.snapshot()
            del self.log[index]
            self.save("Deleted log entry  ·  Ctrl+Z to undo")

        def on_undo(self):
            if not self.undo:
                self.say("Nothing to undo")
                return
            self.tasks, self.log = self.undo.pop()
            self.save("Undone")

        # ── rendering ──
        def render(self):
            for child in self.body.get_children():
                child.destroy()
            pending, done = split_buckets(self.tasks)

            self.body.pack_start(section_label(f"REMAINING · {len(pending)}"), False, False, 0)
            self.body.pack_start(self._list(pending, self._pending_row,
                                            "Nothing left. Add something above."), False, False, 0)
            self.body.pack_start(section_label(f"DONE TODAY · {len(done)}", "section-done"),
                                 False, False, 0)
            self.body.pack_start(self._list(done, self._done_row, "Nothing ticked off yet."),
                                 False, False, 0)
            self.body.pack_start(section_label(f"LOG · {len(self.log)}", "section-log"),
                                 False, False, 0)
            self.body.pack_start(self._list(list(enumerate(self.log)), self._log_row,
                                            "No updates logged today."), False, False, 0)
            self.body.show_all()

        def _list(self, items, make_row, empty):
            lb = Gtk.ListBox()
            lb.set_selection_mode(Gtk.SelectionMode.NONE)
            if not items:
                lbl = Gtk.Label(label=empty, xalign=0)
                lbl.get_style_context().add_class("empty")
                lb.add(lbl)
            for item in items:
                lb.add(make_row(item))
            return lb

        def _check(self, task):
            chk = Gtk.CheckButton()
            chk.set_active(task.done)
            chk.set_can_focus(False)
            chk.set_valign(Gtk.Align.CENTER)
            chk.set_tooltip_text("Mark not done" if task.done else "Mark done")
            chk.connect("toggled", lambda c: self.set_done(task, c.get_active()))
            return chk

        def _pending_row(self, task):
            row = EditableRow(self, task.text, lambda new: self.rename(task, new))
            row.box.pack_start(self._check(task), False, False, 0)
            row.pack_text()
            age = task.age_days()
            if age:
                meta = Gtk.Label(label=f"{age}d")
                meta.set_tooltip_text(f"Added {task.added}, carried over {age} day{'s' if age != 1 else ''}")
                meta.get_style_context().add_class("meta")
                if age >= 3:
                    meta.get_style_context().add_class("meta-old")
                row.box.pack_start(meta, False, False, 0)
            row.box.pack_start(icon_button(ICON_UP, "Move up", lambda: self.move(task, -1)), False, False, 0)
            row.box.pack_start(icon_button(ICON_DOWN, "Move down", lambda: self.move(task, 1)), False, False, 0)
            row.box.pack_start(icon_button(ICON_EDIT, "Edit (or double-click)", row.start_edit), False, False, 0)
            row.box.pack_start(icon_button(ICON_DEL, "Delete", lambda: self.delete(task), True), False, False, 0)
            return row

        def _done_row(self, task):
            row = EditableRow(self, task.text, lambda new: self.rename(task, new),
                              ("task", "task-done"))
            row.box.pack_start(self._check(task), False, False, 0)
            row.pack_text()
            meta = Gtk.Label(label=task.done_at[11:16])
            meta.get_style_context().add_class("meta")
            row.box.pack_start(meta, False, False, 0)
            row.box.pack_start(icon_button(ICON_EDIT, "Edit (or double-click)", row.start_edit), False, False, 0)
            row.box.pack_start(icon_button(ICON_DEL, "Delete", lambda: self.delete(task), True), False, False, 0)
            return row

        def _log_row(self, item):
            index, line = item
            stamp, text = split_log(line)
            row = EditableRow(self, text, lambda new: self.edit_log(index, new))
            meta = Gtk.Label(label=stamp or "·")
            meta.get_style_context().add_class("meta")
            row.box.pack_start(meta, False, False, 0)
            row.pack_text()
            row.box.pack_start(icon_button(ICON_EDIT, "Edit (or double-click)", row.start_edit), False, False, 0)
            row.box.pack_start(icon_button(ICON_DEL, "Delete", lambda: self.delete_log(index), True), False, False, 0)
            return row

        # ── history ──
        def refresh_days(self):
            try:
                days = sorted((f[:-3] for f in os.listdir(DAILY_DIR)
                               if DATE_RE.fullmatch(f[:-3]) and f.endswith(".md")), reverse=True)
            except OSError:
                days = []
            self.day_combo.remove_all()
            for d in days:
                n = len(read_day(d)["done"])
                label = dt.date.fromisoformat(d).strftime("%a %-d %b %Y")
                self.day_combo.append(d, f"{label}   ·   {n} done")
            if days:
                self.day_combo.set_active(0)
            else:
                self.history.set_markup(
                    f"<span color='{OVERLAY}'><i>No daily files yet. They start the "
                    "first day you tick something off or log an update.</i></span>")

        def show_day(self):
            d = self.day_combo.get_active_id()
            if not d:
                return
            out = []
            for raw in read_text(day_path(d)).splitlines():
                e = GLib.markup_escape_text(raw)
                if raw.startswith("# "):
                    out.append(f"<span size='x-large' weight='bold'>{e[2:]}</span>")
                elif raw.startswith("## "):
                    out.append(f"\n<span color='{accent}' weight='bold'>{e[3:]}</span>")
                elif raw.startswith("- [x] "):
                    out.append(f"  <span color='{GREEN}'>✓</span>  {e[6:]}")
                elif raw.startswith("- [ ] "):
                    out.append(f"  <span color='{OVERLAY}'>○</span>  {e[6:]}")
                elif raw.startswith("- "):
                    stamp, text = split_log(raw)
                    out.append(f"  <span color='{PEACH}'>{stamp}</span>  "
                               f"{GLib.markup_escape_text(text)}")
                elif raw == "_nothing_":
                    out.append(f"  <span color='{OVERLAY}'><i>nothing</i></span>")
            self.history.set_markup("\n".join(out))

        def open_day_file(self):
            d = self.day_combo.get_active_id()
            if d:
                Gio.AppInfo.launch_default_for_uri(Gio.File.new_for_path(day_path(d)).get_uri(), None)

        # ── misc ──
        def _on_switch(self, _nb, _page, index):
            if index == 1:
                self.refresh_days()

        def _on_file_changed(self, _mon, _f, _other, event):
            if event not in (Gio.FileMonitorEvent.CHANGES_DONE_HINT, Gio.FileMonitorEvent.CREATED,
                             Gio.FileMonitorEvent.CHANGED):
                return
            if self.editing:
                return  # do not yank the row out from under the cursor
            tasks_now = read_text(TASKS_FILE)
            log_now = read_day(today())["log"]
            if tasks_now != self.last_written or log_now != self.log:
                self.reload()
                self.say("Reloaded: changed outside the panel")

        def _tick(self):
            if today() != self.day and not self.editing:
                self.day = today()
                self.undo.clear()
                self.reload()
                self.say("New day: yesterday's done tasks archived")
            return True

        def say(self, text):
            self.status.set_text(text)

        def say_counts(self):
            pending, done = split_buckets(self.tasks)
            self.say(f"{len(pending)} remaining · {len(done)} done today  ·  "
                     "double-click to edit · Ctrl+Z undo · Esc close")

        def on_key(self, _w, event):
            ctrl = event.state & Gdk.ModifierType.CONTROL_MASK
            if self.editing:
                return False  # the inline entry handles Enter / Escape
            if event.keyval == Gdk.KEY_Escape:
                Gtk.main_quit()
                return True
            if ctrl and event.keyval in (Gdk.KEY_z, Gdk.KEY_Z):
                self.on_undo()
                return True
            if ctrl and event.keyval == Gdk.KEY_l:
                self.notebook.set_current_page(0)
                self.log_entry.grab_focus()
                return True
            if ctrl and event.keyval == Gdk.KEY_n:
                self.notebook.set_current_page(0)
                self.add_entry.grab_focus()
                return True
            return False

    provider = Gtk.CssProvider()
    provider.load_from_data(_rice_subst(css).encode())
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
    win = TasksPanel()
    win.show_all()
    win.add_entry.grab_focus()
    Gtk.main()


def main():
    args = sys.argv[1:]
    cmd = args[0] if args else "panel"
    rest = " ".join(args[1:])
    if cmd == "status":
        cmd_status()
    elif cmd == "toggle":
        cmd_toggle()
    elif cmd == "panel":
        run_panel()
    elif cmd == "quickadd":
        cmd_quickadd()
    elif cmd == "add":
        cmd_add(rest)
    elif cmd == "log":
        if rest.strip():
            add_log(" ".join(rest.split()))
    elif cmd == "list":
        cmd_list()
    elif cmd == "checkin":
        cmd_checkin(args[1] if len(args) > 1 else None)
    else:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
