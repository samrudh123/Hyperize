#!/usr/bin/env python3
"""Screen recording for the top bar's record pill (RecordPill.qml).

Two backends:
  wf-recorder  quick recordings: the screen, a region or a window, with the
               desktop sound, the microphone or no audio. VAAPI H.264 on the
               Intel GPU, libx264 if that fails. Files go to ~/Videos/Recordings.
  OBS          when OBS is running its own recording is driven through
               obs-websocket (Tools -> WebSocket Server Settings; the password
               is read from OBS's config, never stored here). Scenes, output
               folder and format stay whatever OBS is set to.

  screen-record.py start [screen|region|window]   wf-recorder
  screen-record.py obs [start|stop|toggle]        OBS
  screen-record.py stop                           whichever is recording
  screen-record.py toggle                         stop, else OBS if open, else screen
  screen-record.py audio [desktop|mic|none]       wf-recorder's sound source
  screen-record.py watch                          JSON line per change (the pill)

wf-recorder is the Ubuntu .deb unpacked into ~/.local/opt (no sudo), linked as
~/.local/bin/wf-recorder; keybind children do not have ~/.local/bin on PATH,
so it is called by absolute path. `sudo apt install wf-recorder` makes the
/usr/bin one win.
"""
import base64
import hashlib
import json
import os
import shutil
import signal
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

HOME = Path.home()
HYPR = HOME / ".config/hypr"
RUN = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp"))
STATE = RUN / "screen-record.json"          # {pid, started, file, mode}
LOG = RUN / "screen-record.log"
AUDIO_FILE = HYPR / "screen-record-audio"   # desktop | mic | none
OUT_DIR = HOME / "Videos/Recordings"
OBS_WS = HOME / ".config/obs-studio/plugin_config/obs-websocket/config.json"
RENDER_NODE = "/dev/dri/renderD128"


def wf_binary():
    for p in ("/usr/bin/wf-recorder", str(HOME / ".local/bin/wf-recorder")):
        if os.access(p, os.X_OK):
            return p
    return None


def notify(summary, body="", *extra):
    subprocess.run(["notify-send", "-a", "Screen recorder", *extra, summary, body])


def audio_mode():
    try:
        m = AUDIO_FILE.read_text().strip()
    except OSError:
        m = ""
    return m if m in ("desktop", "mic", "none") else "desktop"


def wp_node_name(target):
    """node.name of @DEFAULT_AUDIO_SINK@ / @DEFAULT_AUDIO_SOURCE@."""
    out = subprocess.run(["wpctl", "inspect", target], capture_output=True, text=True).stdout
    for line in out.splitlines():
        line = line.strip().lstrip("* ")
        if line.startswith("node.name"):
            return line.split("=", 1)[1].strip().strip('"')
    return None


# ── wf-recorder ─────────────────────────────────────────────────────────────

def wf_state():
    """The running wf-recorder session, or None (stale state is cleaned up)."""
    try:
        st = json.loads(STATE.read_text())
        os.kill(st["pid"], 0)
        with open(f"/proc/{st['pid']}/comm") as f:
            if "wf-recorder" not in f.read():
                raise ProcessLookupError
        return st
    except (OSError, ValueError, KeyError, ProcessLookupError):
        STATE.unlink(missing_ok=True)
        return None


def palette():
    try:
        pal = json.loads((HYPR / "theme/palette.json").read_text())
    except (OSError, ValueError):
        pal = {}
    try:
        accent = (HYPR / "theme/accent").read_text().strip()
    except OSError:
        accent = "89b4fa"
    return pal.get("crust", "#11111b").lstrip("#"), accent


def slurp(boxes=None):
    crust, accent = palette()
    cmd = ["slurp", "-d", "-b", crust + "aa", "-c", accent + "ff", "-s", "00000000", "-w", "2"]
    if boxes is not None:
        cmd.append("-r")
    r = subprocess.run(cmd, input=boxes, capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


def window_boxes():
    """'x,y wxh title' for every window on a visible workspace (slurp -r)."""
    mons = json.loads(subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True, text=True).stdout)
    visible = {m["activeWorkspace"]["id"] for m in mons} | {m["specialWorkspace"]["id"] for m in mons}
    clients = json.loads(subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True).stdout)
    lines = []
    for c in clients:
        if c["workspace"]["id"] in visible and c.get("mapped", True) and not c.get("hidden"):
            (x, y), (w, h) = c["at"], c["size"]
            lines.append(f"{x},{y} {w}x{h}")
    return "\n".join(lines) + "\n"


def focused_output():
    mons = json.loads(subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True, text=True).stdout)
    return next((m["name"] for m in mons if m.get("focused")), mons[0]["name"] if mons else None)


def wf_start(mode):
    if wf_state() or obs_recording():
        return
    wf = wf_binary()
    if not wf:
        notify("wf-recorder is not installed", "sudo apt install wf-recorder", "-u", "critical")
        return

    if mode == "region":
        geom = slurp()
        if not geom:
            return
        where = ["-g", geom]
    elif mode == "window":
        geom = slurp(window_boxes())
        if not geom:
            return
        where = ["-g", geom]
    else:
        out = focused_output()
        where = ["-o", out] if out else []

    audio = []
    am = audio_mode()
    if am == "desktop":
        sink = wp_node_name("@DEFAULT_AUDIO_SINK@")
        audio = [f"--audio={sink}.monitor"] if sink else ["--audio"]
    elif am == "mic":
        audio = ["--audio"]             # PulseAudio's default source

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    file = OUT_DIR / f"{datetime.now():%Y-%m-%d_%H-%M-%S}.mp4"
    encoders = []
    if os.path.exists(RENDER_NODE):
        encoders.append(["-c", "h264_vaapi", "-d", RENDER_NODE])
    encoders.append(["-c", "libx264", "-p", "preset=veryfast", "-p", "crf=23", "-x", "yuv420p"])

    for enc in encoders:
        with open(LOG, "w") as log:
            p = subprocess.Popen([wf, "-y", *where, *enc, *audio, "-f", str(file)],
                                 stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                                 start_new_session=True)
        time.sleep(0.8)                 # a bad encoder dies at once
        if p.poll() is None:
            STATE.write_text(json.dumps({"pid": p.pid, "started": time.time(),
                                         "file": str(file), "mode": mode, "audio": am}))
            return
    notify("Recording failed to start", f"see {LOG}", "-u", "critical")


def wf_stop():
    st = wf_state()
    if not st:
        return False
    os.kill(st["pid"], signal.SIGINT)   # SIGINT: wf-recorder finalises the file
    for _ in range(100):
        time.sleep(0.1)
        try:
            os.kill(st["pid"], 0)
        except ProcessLookupError:
            break
    STATE.unlink(missing_ok=True)
    saved(Path(st["file"]))
    return True


def saved(file):
    """'Recording saved' with Play / Show in folder / Copy file actions."""
    if not file.exists():
        notify("Recording stopped", "no file was written")
        return
    size = file.stat().st_size / 1e6
    shown = str(file).replace(str(HOME), "~", 1)
    r = subprocess.run(["notify-send", "-a", "Screen recorder", "-i", "video-x-generic",
                        "-A", "play=Play", "-A", "folder=Show in folder", "-A", "copy=Copy file",
                        "Recording saved", f"{shown}  ·  {size:.1f} MB"],
                       capture_output=True, text=True)
    act = r.stdout.strip()
    if act == "play":
        subprocess.Popen(["xdg-open", str(file)], start_new_session=True)
    elif act == "folder":                # yazi grid view, the new file selected
        subprocess.Popen([str(HOME / ".config/yazi/grid-open.sh"), str(file)], start_new_session=True)
    elif act == "copy":
        subprocess.run(["wl-copy", "-t", "text/uri-list"], input=file.as_uri() + "\n", text=True)


# ── OBS (obs-websocket 5) ───────────────────────────────────────────────────

def is_obs(pid):
    try:
        with open(f"/proc/{pid}/comm") as f:
            return f.read().strip() == "obs"
    except OSError:
        return False


def obs_pid():
    return next((p for p in os.listdir("/proc") if p.isdigit() and is_obs(p)), None)


def obs_running():
    return obs_pid() is not None


class Obs:
    """A minimal obs-websocket v5 client (python3-websockets, sync API)."""

    def __init__(self):
        from websockets.sync.client import connect
        cfg = json.loads(OBS_WS.read_text())
        self.ws = connect(f"ws://127.0.0.1:{cfg.get('server_port', 4455)}", open_timeout=2)
        hello = json.loads(self.ws.recv(timeout=2))["d"]
        ident = {"rpcVersion": 1, "eventSubscriptions": 0}
        auth = hello.get("authentication")
        if auth:
            secret = base64.b64encode(hashlib.sha256((cfg["server_password"] + auth["salt"]).encode()).digest())
            ident["authentication"] = base64.b64encode(
                hashlib.sha256(secret + auth["challenge"].encode()).digest()).decode()
        self.ws.send(json.dumps({"op": 1, "d": ident}))
        if json.loads(self.ws.recv(timeout=2)).get("op") != 2:
            raise ConnectionError("obs-websocket refused the login")
        self.n = 0

    def call(self, kind, data=None):
        self.n += 1
        rid = str(self.n)
        self.ws.send(json.dumps({"op": 6, "d": {"requestType": kind, "requestId": rid,
                                                 "requestData": data or {}}}))
        while True:
            m = json.loads(self.ws.recv(timeout=3))
            if m.get("op") == 7 and m["d"].get("requestId") == rid:
                return m["d"].get("responseData") or {}

    def close(self):
        self.ws.close()


def obs_connect():
    try:
        return Obs()
    except Exception:
        return None


def obs_recording():
    if not obs_running():
        return False
    o = obs_connect()
    if not o:
        return False
    try:
        return bool(o.call("GetRecordStatus").get("outputActive"))
    finally:
        o.close()


def obs_cmd(action):
    if not obs_running():
        notify("OBS is not running")
        return
    o = obs_connect()
    if not o:
        notify("Cannot reach OBS",
               "Enable Tools → WebSocket Server Settings → Enable WebSocket server", "-u", "critical")
        return
    try:
        if action in ("start", "toggle") and wf_state():
            notify("Already recording with wf-recorder")
            return
        st = o.call("GetRecordStatus")
        if action == "toggle":
            action = "stop" if st.get("outputActive") else "start"
        if action == "start" and not st.get("outputActive"):
            o.call("StartRecord")
        elif action == "stop" and st.get("outputActive"):
            path = o.call("StopRecord").get("outputPath")
            if path:
                o.close()
                o = None
                saved(Path(path))
    finally:
        if o:
            o.close()


def die_with_parent():
    """SIGTERM us when Quickshell exits: watch() only prints on change, so an
    idle one never hits a broken pipe and outlived every Quickshell restart."""
    import ctypes
    ctypes.CDLL("libc.so.6", use_errno=True).prctl(1, signal.SIGTERM)   # PR_SET_PDEATHSIG


# ── watch: one JSON line per change, for the pill ───────────────────────────

OBS_SCAN = 5      # s between /proc sweeps for OBS in watch() while it is not running


def watch():
    die_with_parent()
    last = None
    obs = None
    # Sweeping all of /proc every second (~450 opens) just to spot OBS was the
    # bulk of this loop's CPU: once found, only its own pid is checked; while
    # absent, the sweep runs every OBS_SCAN s (OBS takes longer than that to
    # bring its websocket up anyway).
    opid, next_scan = None, 0.0
    while True:
        out = {"state": "idle", "backend": "", "elapsed": 0, "obs": False,
               "audio": audio_mode(), "wf": wf_binary() is not None}
        st = wf_state()
        if st:
            out.update(state="recording", backend="wf", elapsed=int(time.time() - st["started"]),
                       mode=st.get("mode", "screen"))
        if opid and not is_obs(opid):
            opid, next_scan = None, 0.0
        if not opid and time.monotonic() >= next_scan:
            opid, next_scan = obs_pid(), time.monotonic() + OBS_SCAN
        if opid:
            out["obs"] = True
            if obs is None:
                obs = obs_connect()
            if obs is not None:
                try:
                    r = obs.call("GetRecordStatus")
                    out["obsReachable"] = True
                    if r.get("outputActive") and not st:
                        out.update(state="paused" if r.get("outputPaused") else "recording",
                                   backend="obs", elapsed=int(r.get("outputDuration", 0) / 1000))
                except Exception:
                    obs = None
        elif obs is not None:
            try:
                obs.close()
            except Exception:
                pass
            obs = None
        line = json.dumps(out)
        if line != last:
            print(line, flush=True)
            last = line
        time.sleep(0.5 if out["state"] != "idle" else 1)


def main():
    args = sys.argv[1:] or ["toggle"]
    cmd = args[0]
    if cmd == "start":
        wf_start(args[1] if len(args) > 1 else "screen")
    elif cmd == "stop":
        if not wf_stop() and obs_running():
            obs_cmd("stop")
    elif cmd == "toggle":
        if wf_stop():
            return
        if obs_running():
            obs_cmd("toggle")
        else:
            wf_start("screen")
    elif cmd == "obs":
        obs_cmd(args[1] if len(args) > 1 else "toggle")
    elif cmd == "audio":
        if len(args) > 1 and args[1] in ("desktop", "mic", "none"):
            AUDIO_FILE.write_text(args[1] + "\n")
        print(audio_mode())
    elif cmd == "watch":
        signal.signal(signal.SIGPIPE, signal.SIG_DFL)
        watch()
    else:
        print(__doc__)
        sys.exit(2)


if __name__ == "__main__":
    main()
