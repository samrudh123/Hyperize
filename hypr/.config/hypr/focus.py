#!/usr/bin/python3
"""Focus timer (pomodoro) — the bottom bar's centre pill, tied to the tasks.

    focus.py start [MIN] [TASK…]   start a focus session (default: the set length)
    focus.py toggle                idle: start · running: pause · paused: resume
    focus.py stop                  end it, nothing logged
    focus.py skip                  finish the current phase now
    focus.py add MIN               add minutes to the current phase
    focus.py task [TEXT]           what this session is for (empty = none)
    focus.py pick                  ask for it (fuzzel): any task or chore, kept
                                   in `recent` for the menu; idle -> starts
    focus.py lengths WORK BREAK    session / short break length in minutes
    focus.py next                  phase over? move on (the bar calls this
                                   when its countdown reaches zero)
    focus.py status                print the state

A session is WORK (do not disturb on) → BREAK (5 min, every 4th 15 min;
notifications back) → idle, with a notification at each end. A finished
session is written to today's log in ~/notes (tasks.py log), with its task.

STATE: ~/.local/state/focus/state.json — the bar watches it, so nothing
polls; the countdown is the bar's own clock against `ends` (epoch seconds).
Survives bar restarts and reboots (an expired phase moves on at once).
"""

import json
import os
import subprocess
import sys
import time

HYPR = os.path.dirname(os.path.abspath(__file__))
STATE_DIR = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")), "focus")
STATE = os.path.join(STATE_DIR, "state.json")
DND_FILE = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
                        "notif-center", "dnd")
LONG_EVERY = 4

DEFAULT = {"phase": "idle", "ends": 0, "left": 0, "total": 0, "paused": False, "task": "",
           "work": 25, "brk": 5, "long": 15, "round": 0, "day": "", "dnd_before": False,
           "recent": []}           # tasks typed via `pick`, newest first (menu rows)
RECENT_MAX = 4


def load():
    try:
        with open(STATE) as f:
            st = {**DEFAULT, **json.load(f)}
    except (OSError, ValueError):
        st = dict(DEFAULT)
    today = time.strftime("%Y-%m-%d")
    if st["day"] != today:              # the round count starts over each day
        st["day"], st["round"] = today, 0
    return st


def save(st):
    os.makedirs(STATE_DIR, exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(st, f)
    os.replace(tmp, STATE)


def dnd(on):
    subprocess.run(["/usr/bin/python3", os.path.join(HYPR, "notif-center.py"), "dnd", "on" if on else "off"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def notify(title, body=""):
    subprocess.Popen(["notify-send", "-a", "Focus", "-i", "alarm-symbolic", title, body],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def remaining(st):
    if st["phase"] == "idle":
        return 0
    return st["left"] if st["paused"] else max(0, st["ends"] - time.time())


def begin(st, phase, minutes):
    st.update(phase=phase, total=minutes * 60, ends=time.time() + minutes * 60, left=0, paused=False)


def start(st, minutes=None, task=None):
    if task is not None:
        st["task"] = task
    if st["phase"] != "work":
        st["dnd_before"] = os.path.exists(DND_FILE)
    begin(st, "work", minutes or st["work"])
    dnd(True)


def end_work(st, finished=True):
    """Leave a WORK phase: notifications back as they were, log it."""
    if not st["dnd_before"]:
        dnd(False)
    mins = round(st["total"] / 60)
    if finished and mins >= 1:
        subprocess.run(["/usr/bin/python3", os.path.join(HYPR, "tasks.py"), "log",
                        f"\U0001F345 {mins} min focus" + (f": {st['task']}" if st["task"] else "")],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def advance(st):
    if st["phase"] == "work":
        end_work(st)
        st["round"] += 1
        long = st["round"] % LONG_EVERY == 0
        brk = st["long"] if long else st["brk"]
        begin(st, "break", brk)
        notify(f"Focus session done — {'long ' if long else ''}break, {brk} min",
               (st["task"] + "\n" if st["task"] else "") + f"Session {st['round']} today")
    elif st["phase"] == "break":
        st.update(phase="idle", ends=0, left=0, total=0, paused=False)
        notify("Break's over", "Click the timer to start the next session")


def ask():
    """fuzzel prompt: what is this session for? (Recent ones are rows in the
    bar's menu, so the prompt is only ever free text.)"""
    out = subprocess.run(["fuzzel", "--dmenu", "--width", "40", "--prompt-only", "Focus on: ",
                          "--placeholder", "any task or chore…"],
                         stdin=subprocess.DEVNULL, capture_output=True, text=True)
    return " ".join(out.stdout.split()) if out.returncode == 0 else ""


def main():
    cmd, args = (sys.argv[1] if len(sys.argv) > 1 else "status"), sys.argv[2:]
    st = load()
    if cmd == "start":
        mins = int(args[0]) if args and args[0].isdigit() else None
        rest = args[1:] if mins else args
        start(st, mins, " ".join(rest) if rest else None)
    elif cmd == "toggle":
        if st["phase"] == "idle":
            start(st)
        elif st["paused"]:
            st.update(paused=False, ends=time.time() + st["left"], left=0)
        else:
            st.update(paused=True, left=remaining(st))
    elif cmd == "stop":
        if st["phase"] == "work":
            end_work(st, finished=False)
        st.update(phase="idle", ends=0, left=0, total=0, paused=False)
    elif cmd == "skip":
        if st["phase"] != "idle":
            if st["phase"] == "work":       # log what was actually done
                st["total"] -= remaining(st)
            advance(st)
    elif cmd == "next":
        if st["phase"] != "idle" and not st["paused"] and time.time() >= st["ends"] - 0.5:
            advance(st)
        else:
            return
    elif cmd == "add":
        secs = int(args[0]) * 60 if args else 300
        if st["phase"] != "idle":
            st["total"] += secs
            if st["paused"]:
                st["left"] += secs
            else:
                st["ends"] += secs
    elif cmd == "task":
        st["task"] = " ".join(args)
    elif cmd == "pick":
        text = ask()
        if not text:
            return
        st = load()                     # the prompt may have sat open a while
        st["recent"] = [text] + [r for r in st["recent"] if r != text][:RECENT_MAX - 1]
        if st["phase"] == "idle":
            start(st, None, text)
        else:
            st["task"] = text
    elif cmd == "lengths":
        st["work"], st["brk"] = int(args[0]), int(args[1])
        st["long"] = st["brk"] * 3
    elif cmd == "status":
        print(json.dumps({**st, "remaining": round(remaining(st))}, ensure_ascii=False))
        return
    else:
        sys.exit(__doc__)
    save(st)


if __name__ == "__main__":
    main()
