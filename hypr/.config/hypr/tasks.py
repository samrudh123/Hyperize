#!/usr/bin/python3
"""Tasks — the bottom bar's to-do icon, its panel, and the daily log.

    tasks.py status          waybar JSON for custom/tasks (count + tooltip)
    tasks.py watch [SEC]     `status` every SEC s (2), a line per change (bar pill)
    tasks.py toggle          open the panel, or close it if it is open
    tasks.py panel           open the panel
    tasks.py quickadd        one-line fuzzel prompt -> new task (right-click)
    tasks.py add TEXT        add a task from a terminal (TEXT may end in @when)
    tasks.py log TEXT        add a timestamped line to today's log
    tasks.py list            print remaining + done today
    tasks.py checkin [morning|midday|evening]
                             the scheduled nudge (tasks-checkin.timer); with no
                             argument the kind is picked from the clock
    tasks.py remind          deadline reminders due now (tasks-deadlines.timer,
                             every minute)
    tasks.py deadlines       open tasks with a deadline, as JSON
    tasks.py json            open tasks + today's done ones, as JSON (the
                             Quickshell tasks popup, TasksPopup.qml)
    tasks.py op ACTION ...   one change, answered with {"ok", "msg"} JSON:
                             add TEXT · done|undone|delete I TEXT ·
                             prio I TEXT N · rename I TEXT NEW · due I TEXT SPEC
                             move I TEXT J TEXT2 (swap two, manual order) ·
                             sort manual|deadline|priority · log TEXT ·
                             logedit N TEXT · logdel N · undo
                             (I = index from `json`, TEXT = the task's text, a
                             check that it is still the same task; SPEC = what
                             follows an @, "" clears the deadline; N = the log
                             line's index). Every change can be undone (30).
    tasks.py day DATE        one day file's Done / Still open / Log, as JSON

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

DEADLINES
A task can have a deadline: a day (meaning the end of it, 23:59:59) or a day
and a time, kept in the comment as "due 2026-10-20" / "due 2026-10-20 17:00".
Set it from the calendar button in the panel, or end the task's text with
@when anywhere a task is typed (panel, quick add, `tasks.py add`):

    @today @tomorrow @fri @20/10 @20oct @2026-10-20 @+3d @2w   a day (end of it)
    @fri 17:00  @tomorrow 5pm  @20/10 9:30am                 a day and a time
    @17:00  @5pm                                            today (tomorrow if past)
    @2h  @30m                                               from now

REPEATING TASKS  "every week" in the comment. Ticking one off leaves it in
today's Done and puts the next one on the list, due the next time round (any
times missed while it sat overdue are skipped):

    @daily  @weekdays  @weekly  @monthly        starting today
    @every mon  @every mon,wed,fri  @every 3d  @every 2w
    ...each optionally with a time:  @every mon 17:00  @weekly 9am

PRIORITY  "prio 1".."prio 3" in the comment; type ! / !! / !!! as a word
anywhere in the text, or click the ! in front of a task in the panel.

Reminder notifications have buttons (left-click it: mako's menu): Mark done,
Remind in 15 min / 1 hour, Tomorrow 9:00. A snooze is one extra reminder; the
marks before the deadline still come.

`remind` (every minute) notifies 1 day, 6 hours, 3 hours, 1 hour and 5 minutes
before, and when it is due; the last three are critical, so they stay up and
show through do-not-disturb. A missed one (laptop asleep) is sent once, late;
setting or changing a deadline sends nothing for the marks already past.
What was sent (and snoozes) is in ~/.local/state/tasks/reminded.json.

ROLLOVER
The first time anything runs on a new day, i.e. the bar's poll a few seconds
after midnight, tasks finished on an earlier day are merged into that day's
file and dropped from tasks.md. Open tasks just stay and show how long they
have been carried.

Normal toplevel window, like network-panel.py and for the same reasons; the
windowrules in hyprland.conf match the app_id set by GLib.set_prgname().
"""

import base64
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

REMIND_STATE = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
                            "tasks", "reminded.json")
# (seconds before the deadline, critical)
REMIND_AT = [(86400, False), (6 * 3600, False), (3 * 3600, False), (3600, True), (300, True), (0, True)]

TASK_RE = re.compile(r"^\s*[-*] \[([ xX])\]\s+(.*?)\s*(?:<!--(.*?)-->)?\s*$")
DATE_RE = re.compile(r"\d{4}-\d{2}-\d{2}")
DUE_RE = re.compile(r"\d{4}-\d{2}-\d{2}(?: \d{2}:\d{2})?")
GLYPH_OPEN, GLYPH_CLEAR = "\U000f0131", "\U000f0132"  # md-checkbox_blank_outline / _marked



def _rice_subst(css):
    """Desktop THEMES (SUPER+SHIFT+T): this CSS is written in Catppuccin Mocha;
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
    __slots__ = ("text", "done_at", "added", "due", "every", "prio")

    def __init__(self, text, done_at="", added="", due="", every="", prio=0):
        self.text = text
        self.done_at = done_at  # "YYYY-MM-DD HH:MM" when done, else ""
        self.added = added      # "YYYY-MM-DD", or "" for hand-written lines
        self.due = due          # "YYYY-MM-DD" (end of day), "YYYY-MM-DD HH:MM", or ""
        self.every = every      # repeat rule ("week", "mon,wed", "3d"...; see RULES), or ""
        self.prio = prio        # 0 none, 1-3 = ! !! !!!

    @property
    def done(self):
        return bool(self.done_at)

    @property
    def done_day(self):
        return self.done_at[:10]

    def copy(self):
        return Task(self.text, self.done_at, self.added, self.due, self.every, self.prio)

    def line(self):
        meta = []
        if self.added:
            meta.append(f"added {self.added}")
        if self.due:
            meta.append(f"due {self.due}")
        if self.every:
            meta.append(f"every {self.every}")
        if self.prio:
            meta.append(f"prio {self.prio}")
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


# ── deadlines ───────────────────────────────────────────────────────────────

DAYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
MONTHS = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]


def due_at(due):
    """The deadline as a datetime: a bare day means its last second."""
    try:
        if len(due) == 10:
            return dt.datetime.combine(dt.date.fromisoformat(due), dt.time(23, 59, 59))
        return dt.datetime.strptime(due, "%Y-%m-%d %H:%M")
    except (TypeError, ValueError):
        return None


def _month(word):
    word = word[:3]
    return MONTHS.index(word) + 1 if word in MONTHS else None


def _dated(year, month, day, base):
    """A day of the month; with no year, the next one that is not past."""
    try:
        if year is not None:
            return dt.date(year + 2000 if year < 100 else year, month, day)
        d = dt.date(base.year, month, day)
        return d if d >= base else dt.date(base.year + 1, month, day)
    except ValueError:
        return None


def parse_day(word):
    t = now().date()
    w = word.lower().rstrip(",")
    if w in ("today", "tod", "tonight", "eod"):
        return t
    if w in ("tomorrow", "tmr", "tmrw", "tom"):
        return t + dt.timedelta(1)
    if len(w) >= 3:
        for i, name in enumerate(DAYS):
            if name.startswith(w):  # the next one; today if it is that day
                return t + dt.timedelta((i - t.weekday()) % 7)
    m = re.fullmatch(r"\+?(\d+)([dw])", w)
    if m:
        return t + dt.timedelta(int(m[1]) * (7 if m[2] == "w" else 1))
    try:
        return dt.date.fromisoformat(w)
    except ValueError:
        pass
    m = re.fullmatch(r"(\d{1,2})[/.](\d{1,2})(?:[/.](\d{2}|\d{4}))?", w)  # day first
    if m:
        return _dated(int(m[3]) if m[3] else None, int(m[2]), int(m[1]), t)
    m = re.fullmatch(r"(\d{1,2})-?([a-z]{3,})", w) or re.fullmatch(r"([a-z]{3,})-?(\d{1,2})", w)
    if m:
        day, mon = (m[1], m[2]) if m[1].isdigit() else (m[2], m[1])
        if _month(mon):
            return _dated(None, _month(mon), int(day), t)
    return None


def parse_time(word, bare=False):
    """'17:00' '9:30am' '5pm' (and '17' if bare) -> (h, m); 'eod' -> 'eod'; else None."""
    w = word.lower().replace(".", ":")
    if w == "eod":
        return "eod"
    m = re.fullmatch(r"(\d{1,2})(?::(\d{2}))?(am|pm)?", w)
    if not m or not (m[2] or m[3] or bare):  # alone, a bare number is not a time
        return None
    h, mi = int(m[1]), int(m[2] or 0)
    if m[3]:
        if not 1 <= h <= 12:
            return None
        h = h % 12 + (12 if m[3] == "pm" else 0)
    return (h, mi) if h < 24 and mi < 60 else None


def parse_due(spec):
    """'fri', 'fri 17:00', '17:00', '2h', '20/10 5pm' ... -> a due string, or None."""
    words = spec.split()
    if not words or len(words) > 2:
        return None
    if len(words) == 1:
        w = words[0].lower()
        m = re.fullmatch(r"\+?(\d+)(m|min|mins|h|hr|hrs)", w)
        if m:
            secs = int(m[1]) * (3600 if m[2].startswith("h") else 60)
            return (now() + dt.timedelta(seconds=secs)).strftime("%Y-%m-%d %H:%M")
        tm = parse_time(w)
        if tm and tm != "eod":
            when = dt.datetime.combine(now().date(), dt.time(*tm))
            if when <= now():
                when += dt.timedelta(1)
            return when.strftime("%Y-%m-%d %H:%M")
    d = parse_day(words[0])
    if d is None:
        return None
    tm = parse_time(words[1], bare=True) if len(words) == 2 else "eod"  # "fri 17"
    if tm is None:
        return None
    return d.isoformat() if tm == "eod" else f"{d.isoformat()} {tm[0]:02d}:{tm[1]:02d}"


def parse_rule(word):
    """'week' 'weekly' 'mon,wed' 'friday' '3d' '2w' ... -> the stored rule, or None."""
    w = word.lower().strip(",")
    alias = {"day": "day", "days": "day", "daily": "day", "weekday": "weekday", "weekdays": "weekday",
             "week": "week", "weeks": "week", "weekly": "week", "month": "month", "months": "month",
             "monthly": "month"}
    if w in alias:
        return alias[w]
    m = re.fullmatch(r"(\d+)([dw])", w)
    if m and int(m[1]) >= 1:
        n = int(m[1])
        return ("day" if m[2] == "d" else "week") if n == 1 else f"{n}{m[2]}"
    picked = set()
    for part in w.split(","):
        hit = [i for i, name in enumerate(DAYS) if len(part) >= 3 and name.startswith(part)]
        if not hit:
            return None
        picked.add(hit[0])
    return ",".join(DAYS[i][:3] for i in sorted(picked)) if picked else None


def rule_days(rule):
    """Weekday numbers of a 'mon,wed' rule, else None."""
    if rule and rule[0].isalpha() and rule not in ("day", "weekday", "week", "month"):
        return {[d[:3] for d in DAYS].index(x) for x in rule.split(",")}
    return None


def rule_label(rule):
    if not rule:
        return ""
    fixed = {"day": "daily", "weekday": "weekdays", "week": "weekly", "month": "monthly"}
    if rule in fixed:
        return fixed[rule]
    m = re.fullmatch(r"(\d+)([dw])", rule)
    if m:
        return f"every {m[1]} {'days' if m[2] == 'd' else 'weeks'}"
    return "every " + ", ".join(x.capitalize() for x in rule.split(","))


def step_day(rule, d):
    """The next day of the series after d."""
    days = rule_days(rule)
    if days is not None or rule == "weekday":
        ok = days if days is not None else {0, 1, 2, 3, 4}
        d += dt.timedelta(1)
        while d.weekday() not in ok:
            d += dt.timedelta(1)
        return d
    if rule == "day":
        return d + dt.timedelta(1)
    if rule == "week":
        return d + dt.timedelta(7)
    if rule == "month":
        def last_day(y, mo):
            return (dt.date(y + (mo == 12), mo % 12 + 1, 1) - dt.timedelta(1)).day
        y, mo = (d.year + 1, 1) if d.month == 12 else (d.year, d.month + 1)
        # the last of a month stays the last (31 Jan -> 28 Feb -> 31 Mar)
        day = last_day(y, mo) if d.day == last_day(d.year, d.month) else min(d.day, last_day(y, mo))
        return dt.date(y, mo, day)
    m = re.fullmatch(r"(\d+)([dw])", rule)
    return d + dt.timedelta(int(m[1]) * (7 if m[2] == "w" else 1))


def with_day(due, d):
    """due moved to day d, keeping its time (or end of day)."""
    return d.isoformat() + due[10:]


def next_due(due, rule):
    """The series' next deadline after due that is still ahead (skips any
    missed while it sat overdue)."""
    d, nxt = due_at(due).date(), due
    for _ in range(4000):
        d = step_day(rule, d)
        nxt = with_day(due, d)
        if due_at(nxt) > now():
            break
    return nxt


def first_due(rule, tm):
    """Where a new series starts: today (or its first weekday from today),
    pushed one step on if the time has already gone."""
    d = now().date()
    ok = rule_days(rule) if rule_days(rule) is not None else ({0, 1, 2, 3, 4} if rule == "weekday" else None)
    while ok is not None and d.weekday() not in ok:
        d += dt.timedelta(1)
    due = d.isoformat() if tm == "eod" else f"{d.isoformat()} {tm[0]:02d}:{tm[1]:02d}"
    return due if due_at(due) > now() else with_day(due, step_day(rule, d))


def parse_spec(spec):
    """What follows an @: a deadline, or a repeat ('every mon 17:00',
    'weekly', 'daily 9am') -> (due, rule), else None."""
    words = spec.lower().split()
    if not words or len(words) > 3:
        return None
    rule, rest = None, words
    if words[0] in ("daily", "weekly", "monthly", "weekdays"):
        rule, rest = parse_rule(words[0]), words[1:]
    elif words[0] == "every" and len(words) >= 2:
        rule, rest = parse_rule(words[1]), words[2:]
        if not rule:
            return None
    if rule:
        if len(rest) > 1:
            return None
        tm = parse_time(rest[0], bare=True) if rest else "eod"
        return (first_due(rule, tm), rule) if tm else None
    due = parse_due(spec)
    return (due, "") if due else None


def split_spec(text):
    """A typed task's markers: ! / !! / !!! anywhere as a word (priority) and
    an @deadline or @repeat at the end.
        'Report !! @fri 5pm' -> ('Report', '2026-10-23 17:00', '', 2, '')
    prio is None when no ! word was typed. An @word at the end that is meant
    as a date but is not one comes back as the last item (else '')."""
    prio, kept = None, []
    for w in text.split():
        if re.fullmatch(r"!{1,3}", w):
            prio = len(w)
        else:
            kept.append(w)
    text = " ".join(kept)
    m = None
    for m in re.finditer(r"(?:^|\s)@(?=\S)", text):
        pass
    if not m:
        return text, "", "", prio, ""
    spec = text[m.end():]
    got = parse_spec(spec)
    if got:
        return text[:m.start()].strip(), got[0], got[1], prio, ""
    words = spec.split()
    meant = (len(words) == 1 or words[0].lower() in ("every", "daily", "weekly", "monthly", "weekdays")
             or (len(words) == 2 and parse_time(words[1], bare=True)))
    return text, "", "", prio, (f"@{words[0]}" if meant and len(words) <= 3 else "")


def split_due(text):
    """split_spec without the extras: (text, due, bad)."""
    text, due, _every, _prio, bad = split_spec(text)
    return text, due, bad


def span(secs):
    """Compact: 25m, 3h, 2d."""
    secs = abs(secs)
    if secs < 3600:
        return f"{max(1, round(secs / 60))}m"
    if secs < 86400:
        return f"{round(secs / 3600)}h"
    return f"{round(secs / 86400)}d"


def span_words(secs):
    secs = abs(secs)
    for unit, size in (("minute", 60), ("hour", 3600), ("day", 86400)):
        n = round(secs / size)
        if unit == "day" or (unit == "minute" and n < 60) or (unit == "hour" and n < 24):
            n = max(1, n)
            return f"{n} {unit}{'s' if n != 1 else ''}"


def due_label(due):
    """Short and relative, for the panel and the bar: 'overdue 2h', 'in 25m',
    'today 17:00', 'tomorrow', 'Fri', '20 Oct 17:00'."""
    when, n = due_at(due), now()
    if not when:
        return ""
    secs = (when - n).total_seconds()
    clock = f" {when:%H:%M}" if len(due) > 10 else ""
    if secs < 0:
        return f"overdue {span(secs)}"
    if secs < 3600:
        return f"in {span(secs)}"
    days = (when.date() - n.date()).days
    if days == 0:
        return "today" + clock
    if days == 1:
        return "tomorrow" + clock
    if days < 7:
        return f"{when:%a}{clock}"
    return f"{when:%-d %b}{clock}" + (f" {when.year}" if when.year != n.year else "")


def due_long(due):
    when = due_at(due)
    if not when:
        return due
    return f"{when:%a %-d %b}" + (f" {when.year}" if when.year != now().year else "") + \
        (f", {when:%H:%M}" if len(due) > 10 else ", end of day")


def due_level(due):
    """'overdue', 'soon' (under a day) or ''."""
    when = due_at(due)
    if not when:
        return ""
    secs = (when - now()).total_seconds()
    return "overdue" if secs < 0 else "soon" if secs < 86400 else ""


def open_line(t):
    """A "Still open" line in the day file."""
    return f"- [ ] {t.text}" + (f" · due {due_long(t.due)}" if t.due else "")


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
        added = done_at = due = every = ""
        prio = 0
        for part in (m.group(3) or "").split(";"):
            part = part.strip()
            if part.startswith("added "):
                added = part[6:].strip()
            elif part.startswith("due ") and DUE_RE.fullmatch(part[4:].strip()):
                due = part[4:].strip()
            elif part.startswith("every ") and parse_rule(part[6:].strip()):
                every = parse_rule(part[6:].strip())
            elif re.fullmatch(r"prio [1-3]", part):
                prio = int(part[5])
            elif part.startswith("done "):
                done_at = part[5:].strip()
        if m.group(1) in "xX" and not done_at:
            # Ticked by hand in an editor: count it as done now.
            done_at, stamp = now().strftime("%Y-%m-%d %H:%M"), True
        if m.group(1) == " ":
            done_at = ""  # unticked by hand
        if every and not due:
            every = ""  # a repeat needs a deadline to repeat from
        tasks.append(Task(m.group(2), done_at, added, due, every, prio))
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
    sec["open"] = [open_line(t) for t in tasks if not t.done]
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
    sec["open"] = [open_line(t) for t in tasks if not t.done]
    write_day(day, sec)


def split_log(line):
    """'- 14:05 text' -> ('14:05', 'text')."""
    m = re.match(r"^- (\d{1,2}:\d{2})\s+(.*)$", line)
    return (m.group(1), m.group(2)) if m else ("", line[2:])


def set_task_done(tasks, task, done):
    """Tick or untick task in tasks (moved to the end, so the done list reads
    in order). Ticking a repeating one puts its next one where it was."""
    if task.done == done:
        return None
    i = tasks.index(task)
    task.done_at = now().strftime("%Y-%m-%d %H:%M") if done else ""
    tasks.remove(task)
    tasks.append(task)
    if not (done and task.every and task.due):
        return None
    nxt = Task(task.text, added=today(), due=next_due(task.due, task.every),
               every=task.every, prio=task.prio)
    task.every = ""  # the series goes on in nxt; this one is history
    tasks.insert(i, nxt)
    return nxt


def find_task(tasks, text, due):
    return next((t for t in tasks if not t.done and t.text == text and t.due == due), None)


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
        lines += [f"  ○  {'!' * t.prio + ' ' if t.prio else ''}{esc(t.text)}"
                  + (f"  · {due_label(t.due)}{' ↻' if t.every else ''}" if t.due else "")
                  for t in pending[:12]]
        if len(pending) > 12:
            lines.append(f"  … {len(pending) - 12} more")
    if done:
        lines.append(f"<b>Done today ({len(done)})</b>")
        lines += [f"  ✓  {esc(t.text)}" for t in done[:8]]
        if len(done) > 8:
            lines.append(f"  … {len(done) - 8} more")
    if not lines:
        lines.append("No tasks yet")
    lines.append("\nClick: tasks · Right-click: new task")
    if pending:
        levels = {due_level(t.due) for t in pending if t.due}
        text = f"{GLYPH_OPEN}  {len(pending)}"
        cls = "overdue" if "overdue" in levels else "due-soon" if "soon" in levels else "pending"
    else:
        text, cls = GLYPH_CLEAR, ("clear" if done else "empty")
    print(json.dumps({"text": text, "tooltip": "\n".join(lines), "class": cls}, ensure_ascii=False))


def panel_pids():
    out = subprocess.run(["pgrep", "-f", f"{SELF} panel"], capture_output=True, text=True)
    return [int(p) for p in out.stdout.split() if int(p) != os.getpid()]


QS = os.path.expanduser("~/.local/bin/qs")


def popup(how="toggle"):
    """the Quickshell tasks popup (TasksPopup.qml) — the panel now; False if
    the shell isn't there (then the GTK panel stands in)"""
    try:
        r = subprocess.run([QS, "ipc", "call", "tasks", how], capture_output=True, text=True, timeout=5)
        return r.returncode == 0 and not r.stderr.strip()
    except (OSError, subprocess.TimeoutExpired):
        return False


def cmd_toggle():
    if popup("toggle"):
        return
    pids = panel_pids()
    if pids:
        for pid in pids:
            os.kill(pid, 15)
        return
    os.execv(sys.executable, [sys.executable, SELF, "panel"])


def cmd_quickadd():
    prompt, text = "New task (@fri 5pm = deadline): ", ""
    while True:
        out = subprocess.run(["fuzzel", "--dmenu", "--prompt-only", prompt, "--search", text],
                             capture_output=True, text=True)
        text = out.stdout.strip()
        if out.returncode != 0 or not text:
            return
        bad = split_spec(text)[4]
        if not bad:
            return cmd_add(text)
        prompt = f"{bad} is not a date (@fri, @tomorrow 5pm, @20/10): "


def cmd_add(text):
    text, due, every, prio, bad = split_spec(" ".join(text.split()))
    if bad:
        sys.exit(f"tasks: {bad} is not a date I know (try @fri, @tomorrow 5pm, @20/10, @2h, @every mon)")
    if not text:
        return
    tasks = load()
    tasks.append(Task(text, added=today(), due=due, every=every, prio=prio or 0))
    commit(tasks)


def cmd_deadlines():
    """Open tasks with a deadline, as JSON (for scripts; the bar's calendar
    reads tasks.md itself)."""
    print(json.dumps([{"text": t.text, "due": t.due, "every": t.every, "prio": t.prio,
                       "label": due_label(t.due), "level": due_level(t.due)}
                      for t in sorted((t for t in load() if t.due and not t.done), key=lambda t: due_at(t.due))],
                     ensure_ascii=False))


def task_json(i, t):
    return {"i": i, "text": t.text, "done": t.done, "doneAt": t.done_at[11:16] if t.done else "",
            "due": t.due, "dueDay": t.due[:10], "dueTime": t.due[11:16], "every": t.every,
            "rule": rule_label(t.every) if t.every else "", "prio": t.prio,
            "label": due_label(t.due) if t.due else "", "long": due_long(t.due) if t.due else "",
            "level": due_level(t.due) if t.due else "", "age": t.age_days(), "added": t.added}


POP_SORTS = ("manual", "deadline", "priority")
POP_STATE = os.path.join(os.path.dirname(REMIND_STATE), "panel.json")     # the GTK panel's too
# (a test run's notes dir keeps its own, so testing can't undo into the real list)
UNDO_FILE = os.path.join(NOTES, ".undo.json") if os.environ.get("TASKS_NOTES_DIR") \
    else os.path.join(os.path.dirname(REMIND_STATE), "undo.json")


def pop_sort():
    try:
        s_ = json.loads(read_text(POP_STATE) or "{}").get("sort", "manual")
    except ValueError:
        s_ = "manual"
    return s_ if s_ in POP_SORTS else "manual"


def past_days():
    try:
        days = sorted((f[:-3] for f in os.listdir(DAILY_DIR)
                       if f.endswith(".md") and DATE_RE.fullmatch(f[:-3])), reverse=True)
    except OSError:
        days = []
    return [{"day": d, "label": dt.date.fromisoformat(d).strftime("%a %-d %b"),
             "done": len(read_day(d)["done"])} for d in days[:60]]


def undo_stack():
    try:
        st = json.loads(read_text(UNDO_FILE) or "[]")
        return st if isinstance(st, list) else []
    except ValueError:
        return []


def snapshot():
    """before a change: tasks.md + today's day file, for `op undo`"""
    st = undo_stack()
    day = today()
    st.append({"day": day, "tasks": read_text(TASKS_FILE), "dayfile": read_text(day_path(day))})
    os.makedirs(os.path.dirname(UNDO_FILE), exist_ok=True)
    atomic_write(UNDO_FILE, json.dumps(st[-30:]))


def cmd_json():
    day = today()
    tasks = load()
    log = [{"i": n, "stamp": split_log(l)[0], "text": split_log(l)[1]} for n, l in enumerate(read_day(day)["log"])]
    print(json.dumps({"today": day, "sort": pop_sort(), "undo": len(undo_stack()), "log": log,
                      "days": past_days(),
                      "tasks": [task_json(i, t) for i, t in enumerate(tasks)
                                if not t.done or t.done_day == day]}, ensure_ascii=False))


def cmd_day(day):
    if not DATE_RE.fullmatch(day or ""):
        return print(json.dumps({}))
    sec = read_day(day)
    strip = lambda l: re.sub(r"^- \[[ xX]\] ", "", l)
    print(json.dumps({"day": day, "title": dt.date.fromisoformat(day).strftime("%A, %-d %B %Y"),
                      "done": [strip(l) for l in sec["done"]], "open": [strip(l) for l in sec["open"]],
                      "log": [{"stamp": split_log(l)[0], "text": split_log(l)[1]} for l in sec["log"]],
                      "path": day_path(day)}, ensure_ascii=False))


def cmd_op(args):
    """One change from the Quickshell popup; prints {"ok": bool, "msg": str}."""
    def reply(ok, msg):
        print(json.dumps({"ok": ok, "msg": msg}, ensure_ascii=False))
    bad_date = "{} is not a date I know: try @fri, @tomorrow 5pm, @20/10, @2h, @every mon"
    action = args[0] if args else ""
    if action == "undo":
        st = undo_stack()
        if not st:
            return reply(False, "Nothing to undo")
        last = st.pop()
        atomic_write(TASKS_FILE, last["tasks"])
        if last.get("dayfile"):
            atomic_write(day_path(last["day"]), last["dayfile"])
        elif os.path.exists(day_path(last["day"])):
            os.remove(day_path(last["day"]))
        atomic_write(UNDO_FILE, json.dumps(st))
        return reply(True, "Undone")
    if action == "sort":
        mode = args[1] if len(args) > 1 else ""
        if mode not in POP_SORTS:
            return reply(False, "sort: manual, deadline or priority")
        os.makedirs(os.path.dirname(POP_STATE), exist_ok=True)
        try:
            st = json.loads(read_text(POP_STATE) or "{}")
        except ValueError:
            st = {}
        st["sort"] = mode
        atomic_write(POP_STATE, json.dumps(st))
        return reply(True, f"Sorted by {mode}")
    if action in ("log", "logedit", "logdel"):
        day = today()
        sec = read_day(day)
        if action == "log":
            text = " ".join(" ".join(args[1:]).split())
            if not text:
                return reply(False, "Type an update first")
            snapshot()
            add_log(text)
            return reply(True, "Logged to today's file")
        if len(args) < 2 or not args[1].isdigit() or int(args[1]) >= len(sec["log"]):
            return reply(False, "That log line changed meanwhile")
        n = int(args[1])
        snapshot()
        if action == "logdel":
            del sec["log"][n]
            msg = "Deleted log entry"
        else:
            text = " ".join(" ".join(args[2:]).split())
            if not text:
                return reply(False, "A log entry needs some text")
            stamp, _ = split_log(sec["log"][n])
            sec["log"][n] = f"- {stamp} {text}" if stamp else f"- {text}"
            msg = "Edited log entry"
        write_day(day, sec)
        return reply(True, msg)
    if action == "add":
        text, due, every, prio, bad = split_spec(" ".join(" ".join(args[1:]).split()))
        if bad:
            return reply(False, bad_date.format(bad))
        if not text:
            return reply(False, "Type a task first")
        tasks = load()
        snapshot()
        tasks.append(Task(text, added=today(), due=due, every=every, prio=prio or 0))
        commit(tasks)
        return reply(True, f"Added “{text}”" + (f" · due {due_long(due)}" if due else ""))
    if len(args) < 3 or not args[1].lstrip("-").isdigit():
        return reply(False, "usage: op ACTION INDEX TEXT [ARG]")
    tasks = load()
    i, text = int(args[1]), args[2]
    t = tasks[i] if 0 <= i < len(tasks) and tasks[i].text == text else \
        next((x for x in tasks if x.text == text), None)
    if not t:
        return reply(False, "That task changed meanwhile — have another look")
    arg = args[3] if len(args) > 3 else ""
    snapshot()
    if action == "move":
        j, jtext = (int(args[3]) if len(args) > 3 and args[3].lstrip("-").isdigit() else -1), \
            (args[4] if len(args) > 4 else "")
        u = tasks[j] if 0 <= j < len(tasks) and tasks[j].text == jtext else \
            next((x for x in tasks if x.text == jtext and not x.done), None)
        if not u:
            return reply(False, "That task changed meanwhile — have another look")
        a, b = tasks.index(t), tasks.index(u)
        tasks[a], tasks[b] = tasks[b], tasks[a]
        commit(tasks)
        return reply(True, "")
    if action in ("done", "undone"):
        nxt = set_task_done(tasks, t, action == "done")
        msg = (f"Done: “{t.text}”" + (f" · next one due {due_long(nxt.due)}" if nxt else "")
               if action == "done" else f"Back on the list: “{t.text}”")
    elif action == "delete":
        tasks.remove(t)
        msg = f"Deleted “{t.text}”"
    elif action == "prio":
        t.prio = int(arg) % 4 if arg.isdigit() else (t.prio + 1) % 4
        msg = ("No priority" if not t.prio else "!" * t.prio) + f": “{t.text}”"
    elif action == "rename":
        new, due, every, prio, bad = split_spec(" ".join(arg.split()))
        if bad:
            return reply(False, bad_date.format(bad))
        if not new:
            return reply(False, "A task needs some text")
        t.text = new
        if due:
            t.due, t.every = due, every
        if prio is not None:
            t.prio = prio
        msg = "Edited"
    elif action == "due":
        spec = arg.strip().lstrip("@")
        if not spec:
            t.due, t.every = "", ""
            msg = f"No deadline: “{t.text}”"
        else:
            got = parse_spec(spec)
            if not got:
                return reply(False, bad_date.format("@" + spec))
            t.due, t.every = got
            msg = f"Due {due_long(t.due)}" + (f", {rule_label(t.every)}" if t.every else "")
    else:
        return reply(False, "unknown action " + action)
    commit(tasks)
    reply(True, msg)


def cmd_list():
    pending, done = split_buckets(load())
    print(f"Remaining ({len(pending)})")
    for t in pending:
        age = t.age_days()
        print(f"  [ ] {'!' * t.prio + ' ' if t.prio else ''}{t.text}" + (f"   ({age}d)" if age else "") +
              (f"   due {due_long(t.due)} ({due_label(t.due)})" if t.due else "") +
              (f"   {rule_label(t.every)}" if t.every else ""))
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
        rows = [f"{mark} {t.text}" + (f"  (due {due_label(t.due)})" if t.due and not t.done else "")
                for t in items[:limit]]
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

    if notify(title, body) == "default":
        open_panel()


def open_panel():
    if popup("open") or panel_pids():
        return
    # Through Hyprland, not Popen: a child of a oneshot service would be
    # killed with the service's cgroup the moment the service returns.
    subprocess.run(["hyprctl", "dispatch", "exec", f"{sys.executable} {SELF} panel"],
                   capture_output=True)


class state_lock:
    """flock around reminded.json's read-modify-write: the minute run and a
    notification's Snooze button both write it."""

    def __enter__(self):
        import fcntl
        os.makedirs(os.path.dirname(REMIND_STATE), exist_ok=True)
        self.fh = open(REMIND_STATE + ".lock", "w")
        fcntl.flock(self.fh, fcntl.LOCK_EX)
        try:
            raw = json.loads(read_text(REMIND_STATE) or "{}")
        except ValueError:
            raw = {}
        # {key: {"marks": [...], "snooze": "YYYY-MM-DD HH:MM" | ""}}; a bare
        # list is the first version's marks
        self.state = {k: (v if isinstance(v, dict) else {"marks": v, "snooze": ""}) for k, v in raw.items()}
        self.before = json.dumps(self.state, sort_keys=True)
        return self.state

    def __exit__(self, *exc):
        if not exc[0] and json.dumps(self.state, sort_keys=True) != self.before:
            atomic_write(REMIND_STATE, json.dumps(self.state, indent=1))
        self.fh.close()


def remind_key(t):
    return f"{t.text}\n{t.due}"


def cmd_remind():
    """Send the deadline reminders that are due (tasks-deadlines.timer, every
    minute). Each mark in REMIND_AT is sent once per task + deadline. A
    deadline seen for the first time (just set or changed) only records the
    marks that were already past when it was set, so setting one never
    notifies straight away; "when it was set" is tasks.md's mtime, because
    this runs up to a minute later and a mark can pass in between (set at
    21:15:03 for 21:16, first seen 21:16:00: its "due now" must still come).
    A snooze (the notification's buttons) is sent once when its time comes."""
    tasks = load()
    fire, n = [], now()
    try:
        set_at = min(n, dt.datetime.fromtimestamp(os.path.getmtime(TASKS_FILE)))
    except OSError:
        set_at = n
    with state_lock() as state:
        keep = {}
        for t in tasks:
            when = due_at(t.due) if t.due and not t.done else None
            if not when:
                continue
            key = remind_key(t)
            rem = (when - n).total_seconds()
            crossed = [mark for mark, _ in REMIND_AT if rem <= mark]
            old = state.get(key)
            if old is None:  # first sight: what was already past when it was set
                old = {"marks": [mark for mark, _ in REMIND_AT if (when - set_at).total_seconds() <= mark],
                       "snooze": ""}
            entry = {"marks": sorted(set(old["marks"]) | set(crossed)), "snooze": old["snooze"]}
            new = [mark for mark in crossed if mark not in old["marks"]]
            if new:
                fire.append((t, min(new), rem))  # several missed (asleep): the latest only
            snooze = due_at(entry["snooze"]) if entry["snooze"] else None
            if entry["snooze"] and (snooze is None or snooze <= n):
                if snooze and not new:  # a mark this minute says it already
                    fire.append((t, None, rem))
                entry["snooze"] = ""
            keep[key] = entry
        state.clear()
        state.update(keep)
    for t, mark, rem in fire:
        critical = dict(REMIND_AT)[mark] if mark is not None else rem <= 3600
        if mark is None:
            head = "Reminder"
        elif mark == 0:
            head = "Due now" if rem > -120 else f"Overdue by {span_words(rem)}"
        else:
            head = f"Due in {span_words(rem)}"
        if mark is None:
            head += f" (due {'in ' + span_words(rem) if rem > 0 else span_words(rem) + ' ago'})"
        note = {"title": f"{head}: {'!' * t.prio + ' ' if t.prio else ''}{t.text}",
                "body": f"Deadline: {due_long(t.due)}" + (f" · {rule_label(t.every)}" if t.every else ""),
                "critical": critical, "text": t.text, "due": t.due}
        arg = base64.urlsafe_b64encode(json.dumps(note).encode()).decode()
        # Its own process (through Hyprland, see open_panel) so it can wait
        # for its buttons as long as it stays up without holding up the next
        # minute's run.
        cmd = f"{sys.executable} {SELF} notify-due {arg}"
        if subprocess.run(["hyprctl", "dispatch", "exec", cmd], capture_output=True).returncode != 0:
            cmd_notify_due(arg)


def reminder_actions(due):
    acts = [("default", "Open tasks"), ("done", "Mark done"),
            ("snooze-15", "Remind in 15 min"), ("snooze-60", "Remind in 1 hour")]
    morning = dt.datetime.combine(now().date() + dt.timedelta(1), dt.time(9))
    when = due_at(due)
    if when and when > morning:
        acts.append(("snooze-tomorrow", "Tomorrow 9:00"))
    return acts


def cmd_notify_due(arg):
    note = json.loads(base64.urlsafe_b64decode(arg.encode()))
    acts = reminder_actions(note.get("due", ""))
    if note["critical"]:  # stays up (mako: urgency=high); waits for a click or a dismiss
        action = notify(note["title"], note["body"], timeout_ms=0, urgency=2, wait_s=12 * 3600, actions=acts)
    else:
        action = notify(note["title"], note["body"], timeout_ms=60000, actions=acts)
    if action == "default":
        open_panel()
    elif action == "done":
        tasks = load()
        t = find_task(tasks, note.get("text"), note.get("due"))
        if t:
            set_task_done(tasks, t, True)
            commit(tasks)
    elif action and action.startswith("snooze-"):
        if action == "snooze-tomorrow":
            at = dt.datetime.combine(now().date() + dt.timedelta(1), dt.time(9))
        else:
            at = now() + dt.timedelta(minutes=int(action.split("-")[1]))
        with state_lock() as state:
            key = f"{note.get('text')}\n{note.get('due')}"
            entry = state.setdefault(key, {"marks": [], "snooze": ""})
            entry["snooze"] = at.strftime("%Y-%m-%d %H:%M")


def notify(title, body, timeout_ms=20000, urgency=1, wait_s=None, actions=(("default", "Open tasks"),)):
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
                [x for pair in actions for x in pair], {"urgency": GLib.Variant("y", urgency)}, timeout_ms)),
            GLib.VariantType("(u)"), Gio.DBusCallFlags.NONE, -1, None)
    except GLib.Error:
        return None  # no notification daemon running
    state["id"] = reply.unpack()[0]
    GLib.timeout_add_seconds(wait_s or (timeout_ms // 1000 + 5), loop.quit)
    loop.run()
    if state.get("action"):
        # mako runs the action but leaves the notification up, and a critical
        # one never expires: close it, the button has been answered.
        try:
            bus.call_sync("org.freedesktop.Notifications", "/org/freedesktop/Notifications",
                          "org.freedesktop.Notifications", "CloseNotification",
                          GLib.Variant("(u)", (state["id"],)), None, Gio.DBusCallFlags.NONE, -1, None)
        except GLib.Error:
            pass
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
    CRUST = "#11111b"
    TEXT, SUBTEXT, OVERLAY = "#cdd6f4", "#a6adc8", "#6c7086"
    GREEN, RED, PEACH, YELLOW = "#a6e3a1", "#f38ba8", "#fab387", "#f9e2af"

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
    button.due {{
        background: alpha({SURFACE0}, 0.6); color: {SUBTEXT}; padding: 1px 7px;
        min-width: 0; min-height: 0; font-size: 8.5pt; border-radius: 5px;
        font-family: "JetBrainsMono Nerd Font";
    }}
    button.due:hover {{ background: {SURFACE1}; color: {TEXT}; }}
    button.due.due-soon {{ color: {PEACH}; }}
    button.due.due-overdue {{ color: {RED}; background: alpha({RED}, 0.15); }}
    .toolbar button.due {{ padding: 5px 10px; font-size: 11pt; }}
    .toolbar button.due.due-set {{ color: {accent}; }}
    .scrim {{ background: alpha({CRUST}, 0.45); }}
    .picker {{
        background: {MANTLE}; border: 1px solid {SURFACE1}; border-radius: 8px;
        box-shadow: 0 6px 18px alpha({CRUST}, 0.6);
    }}
    .picker .due-head {{ color: {accent}; font-size: 8.5pt; font-weight: 700; }}
    .picker .hint {{ color: {OVERLAY}; font-size: 8.5pt; }}
    calendar {{
        background: {SURFACE0}; color: {TEXT}; border: none; border-radius: 6px;
        padding: 4px;
    }}
    calendar.header {{ background: transparent; border: none; color: {TEXT}; }}
    calendar.button {{ color: {SUBTEXT}; background: transparent; }}
    calendar.button:hover {{ color: {accent}; }}
    calendar:selected {{ background: {accent}; color: {BASE}; border-radius: 4px; }}
    calendar:indeterminate {{ color: {SURFACE1}; }}
    entry.bad {{ box-shadow: inset 0 0 0 2px {RED}; }}
    spinbutton.clock {{
        background: {SURFACE0}; border: none; border-radius: 6px; box-shadow: none; padding: 0 4px;
    }}
    spinbutton.clock entry {{
        background: transparent; box-shadow: none; padding: 0; min-height: 0;
        font-size: 15pt; font-weight: 700; color: {TEXT};
    }}
    spinbutton.clock button {{
        background: transparent; color: {OVERLAY}; border: none; box-shadow: none;
        padding: 0; min-height: 14px;
    }}
    spinbutton.clock button:hover {{ color: {accent}; }}
    .colon {{ font-size: 15pt; font-weight: 700; color: {OVERLAY}; }}
    button.prio {{
        background: transparent; padding: 0 2px; min-width: 14px; min-height: 0;
        font-weight: 800; font-size: 10pt; color: transparent;
    }}
    row:hover button.prio.prio-0 {{ color: {SURFACE1}; }}
    button.prio.prio-0:hover {{ color: {OVERLAY}; background: transparent; }}
    button.prio.prio-1 {{ color: {YELLOW}; }}
    button.prio.prio-2 {{ color: {PEACH}; }}
    button.prio.prio-3 {{ color: {RED}; }}
    .section-soon {{ color: {PEACH}; }}
    button.sort {{
        background: transparent; color: {OVERLAY}; font-size: 8pt; padding: 8px 10px 2px;
        min-height: 0;
    }}
    button.sort:hover {{ color: {accent}; background: transparent; }}
    combobox button {{ padding: 4px 8px; }}
    """

    ICON_UP, ICON_DOWN = "\U000f005d", "\U000f0045"     # md-arrow_up / _down
    ICON_EDIT, ICON_DEL = "\U000f03eb", "\U000f01b4"    # md-pencil / md-delete
    ICON_DUE, ICON_DUE_ADD = "\U000f00f0", "\U000f00f3"  # md-calendar_clock / _plus
    PRIO_NAMES = ("no priority", "priority: low", "priority: medium", "priority: high")
    SORTS = ("manual", "deadline", "priority")
    PANEL_STATE = os.path.join(os.path.dirname(REMIND_STATE), "panel.json")
    REPEATS = (("", "Does not repeat"), ("day", "Daily"), ("weekday", "Weekdays"),
               ("week", "Weekly"), ("month", "Monthly"))

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

    class Picker:
        """The deadline picker as a card on a dimmed backdrop inside the
        panel's own window (a Gtk.Overlay child), placed under its anchor.
        Not a Gtk.Popover: on Wayland GTK3 makes popovers a separate
        subsurface, and Hyprland put their input off from where they were
        drawn (clicks landed beside what the pointer was on) and gave them
        their own opacity (the list showed through). Click the backdrop or
        Escape to close."""

        def __init__(self, overlay, anchor, on_closed):
            self.overlay, self.on_closed, self.open = overlay, on_closed, True
            self.scrim = Gtk.EventBox()
            self.scrim.get_style_context().add_class("scrim")
            self.scrim.connect("button-press-event", lambda *_: self.popdown() or True)
            self.card = Gtk.EventBox()  # swallows clicks on the card's gaps
            self.card.get_style_context().add_class("picker")
            self.card.connect("button-press-event", lambda *_: True)
            self.card.set_halign(Gtk.Align.CENTER)
            self.card.set_valign(Gtk.Align.START)
            self.anchor = anchor

        def add(self, child):
            self.card.add(child)

        def popup(self):
            win = self.overlay.get_toplevel()
            self.overlay.add_overlay(self.scrim)
            self.overlay.add_overlay(self.card)
            self.scrim.show_all()
            self.card.show_all()
            # under the anchor, or above it when there is no room below
            h = self.card.get_preferred_height()[1]
            total = self.overlay.get_allocated_height() or win.get_allocated_height()
            xy = self.anchor.translate_coordinates(self.overlay, 0, 0)
            top = 8
            if xy:
                below = xy[1] + self.anchor.get_allocated_height() + 4
                top = below if below + h <= total - 8 else xy[1] - h - 4
            self.card.set_margin_top(max(8, min(top, total - h - 8)))

        def popdown(self):
            if not self.open:
                return
            self.open = False
            self.scrim.destroy()
            self.card.destroy()
            self.on_closed()

    def due_popover(overlay, anchor, current, every, on_pick, on_closed):
        """Quick days, a calendar, a time (empty = end of day) and a repeat
        for one deadline. on_pick(due, every); ("", "") is No deadline."""
        pop = Picker(overlay, anchor, on_closed)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=10)
        pop.add(box)
        head = Gtk.Label(label="DEADLINE", xalign=0)
        head.get_style_context().add_class("due-head")
        box.pack_start(head, False, False, 0)

        when = due_at(current) if current else None
        timed = bool(when and len(current) > 10)

        # The time: hour and minute wheels. The +/- buttons and ↑↓ move one
        # (hour / minute); scrolling, for getting far fast, moves two steps
        # per notch: 2 hours, or 10 minutes (snapped to fives, carrying into
        # the hour). Scroll up = +, down = -; Shift+scroll = one step. Or type.
        # "End of day" (23:59:59) is the default; touching a wheel unticks it.
        def wheel(value, top, tip):
            sp = Gtk.SpinButton(adjustment=Gtk.Adjustment(value=value, lower=0, upper=top,
                                                          step_increment=1, page_increment=10),
                                digits=0, numeric=True)
            sp.set_orientation(Gtk.Orientation.VERTICAL)
            sp.set_wrap(True)
            sp.set_width_chars(2)
            sp.set_alignment(0.5)
            sp.set_tooltip_text(tip)
            sp.get_style_context().add_class("clock")
            sp.connect("output", lambda w: (w.set_text(f"{int(w.get_value()):02d}"), True)[1])
            # A touchpad only sends smooth scrolls, and GTK3 drops those for
            # windows that did not ask for them (a mouse wheel also sends
            # plain up/down, which is why only the wheel worked). Before
            # realize, so the spin button's own windows get the mask.
            sp.add_events(Gdk.EventMask.SCROLL_MASK | Gdk.EventMask.SMOOTH_SCROLL_MASK)
            return sp

        hours = wheel(when.hour if timed else 23, 23, "Hour · scroll: ±2 (Shift: ±1) · +/−, ↑↓ or type")
        mins = wheel(when.minute if timed else 59, 59, "Minutes · scroll: ±10 (Shift: ±1) · +/−, ↑↓ or type")
        eod = Gtk.CheckButton(label="End of day")
        eod.set_active(not timed)
        quiet = [False]  # setting the wheels from "End of day" is not a touch

        def touched(_w):
            if not quiet[0]:
                eod.set_active(False)

        def on_eod(_c):
            if eod.get_active():
                quiet[0] = True
                hours.set_value(23)
                mins.set_value(59)
                quiet[0] = False

        SCROLL_STEPS = 2       # per notch
        TOUCHPAD_NOTCH = 1.0   # touchpad scroll distance (GTK units) that counts as one notch

        def bump(unit, n, fine):
            """n notches (+ up, - down)."""
            h, m = int(hours.get_value()), int(mins.get_value())
            k = n if fine else n * SCROLL_STEPS
            if unit == "h":
                total = ((h + k) % 24) * 60 + m
            elif fine:
                total = h * 60 + m + k
            else:  # k five-minute steps, landing on a multiple of 5
                total = h * 60 + (m // 5 + k) * 5 if k > 0 else h * 60 + ((m + 4) // 5 + k) * 5
            h, m = divmod(total % 1440, 60)
            hours.set_value(h)
            mins.set_value(m)

        acc = {}
        seen = {}  # GTK3 on Wayland sends a wheel notch twice (discrete + smooth), same timestamp

        def on_scroll(w, ev, unit):
            if seen.get(unit) == ev.time:  # the other half of a notch already counted
                return True
            seen[unit] = ev.time
            if ev.direction == Gdk.ScrollDirection.UP:
                n = 1
            elif ev.direction == Gdk.ScrollDirection.DOWN:
                n = -1
            elif ev.direction == Gdk.ScrollDirection.SMOOTH:
                dy = ev.get_scroll_deltas()[2]
                src = ev.get_source_device()
                if src and src.get_source() == Gdk.InputSource.MOUSE:
                    # a wheel: one event per notch (GTK3 on Wayland drops the
                    # plain up/down copy once smooth scrolls are asked for,
                    # and the delta is ~1.5 a notch, so count events, not size)
                    if not dy:
                        return True
                    n = -1 if dy > 0 else 1
                else:
                    # a touchpad: fractions as the fingers move, about one
                    # notch per centimetre. Fingers up = +, down = − (the
                    # user's choice; the opposite of the wheel's sign under
                    # natural scrolling, where fingers up scroll "down")
                    acc[unit] = acc.get(unit, 0.0) + dy / TOUCHPAD_NOTCH
                    n = int(acc[unit])
                    acc[unit] -= n
                    if ev.is_scroll_stop_event():
                        acc[unit] = 0.0
                    if not n:
                        return True
            else:
                return False
            bump(unit, n, bool(ev.state & Gdk.ModifierType.SHIFT_MASK))
            return True

        for w, unit in ((hours, "h"), (mins, "m")):
            w.connect("value-changed", touched)
            w.connect("scroll-event", on_scroll, unit)
        eod.connect("toggled", on_eod)

        def clock():
            """'' (end of day) or ' HH:MM'."""
            if eod.get_active():
                return ""
            hours.update()  # take a value typed but not yet entered
            mins.update()
            return f" {int(hours.get_value()):02d}:{int(mins.get_value()):02d}"

        repeat = Gtk.ComboBoxText()
        for rid, label in REPEATS:
            repeat.append(rid, label)
        if every and every not in dict(REPEATS):
            label = rule_label(every)
            repeat.append(every, label[:1].upper() + label[1:])
        repeat.set_active_id(every or "")

        def pick(day):
            c = clock()
            if c is not None:
                pop.popdown()
                on_pick(day.isoformat() + c, repeat.get_active_id() or "")

        t = now().date()
        quick = Gtk.Box(spacing=4, homogeneous=True)
        for label, d in (("Today", t), ("Tomorrow", t + dt.timedelta(1)),
                         (f"{t + dt.timedelta(7):%a} +1w", t + dt.timedelta(7))):
            b = Gtk.Button(label=label)
            b.connect("clicked", lambda _b, d=d: pick(d))
            quick.pack_start(b, True, True, 0)
        box.pack_start(quick, False, False, 0)

        cal = Gtk.Calendar()
        start = when.date() if when else t
        cal.select_month(start.month - 1, start.year)
        cal.select_day(start.day)

        def cal_day():
            y, m0, d = cal.get_date()
            return dt.date(y, m0 + 1, d)
        cal.connect("day-selected-double-click", lambda _c: pick(cal_day()))
        box.pack_start(cal, False, False, 0)

        trow = Gtk.Box(spacing=6)
        tl = Gtk.Label(label="Time")
        tl.get_style_context().add_class("hint")
        trow.pack_start(tl, False, False, 0)
        trow.pack_start(hours, False, False, 0)
        colon = Gtk.Label(label=":")
        colon.get_style_context().add_class("colon")
        trow.pack_start(colon, False, False, 0)
        trow.pack_start(mins, False, False, 0)
        trow.pack_end(eod, False, False, 0)
        for w in (hours, mins):
            w.connect("activate", lambda _w: pick(cal_day()))
        box.pack_start(trow, False, False, 0)

        rrow = Gtk.Box(spacing=8)
        rl = Gtk.Label(label="Repeat")
        rl.get_style_context().add_class("hint")
        rrow.pack_start(rl, False, False, 0)
        rrow.pack_start(repeat, True, True, 0)
        box.pack_start(rrow, False, False, 0)

        brow = Gtk.Box(spacing=6)
        clear = Gtk.Button(label="No deadline")
        clear.connect("clicked", lambda _b: (pop.popdown(), on_pick("", "")))
        brow.pack_start(clear, False, False, 0)
        hint = Gtk.Label(label="double-click a day = set")
        hint.get_style_context().add_class("hint")
        brow.pack_start(hint, True, True, 0)
        setb = Gtk.Button(label="Set")
        setb.get_style_context().add_class("suggested-action")
        setb.connect("clicked", lambda _b: pick(cal_day()))
        brow.pack_end(setb, False, False, 0)
        box.pack_start(brow, False, False, 0)

        box.show_all()
        pop.popup()
        cal.grab_focus()
        return pop

    def section_head(text, extra=None, button=None):
        box = Gtk.Box()
        box.pack_start(section_label(text, extra), True, True, 0)
        if button:
            box.pack_end(button, False, False, 0)
        return box

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
            self.popover = None   # the open deadline picker, if any
            self.new_due = ""     # deadline picked for the task being typed
            self.new_every = ""
            try:
                self.sort = json.loads(read_text(PANEL_STATE) or "{}").get("sort", "manual")
            except ValueError:
                self.sort = "manual"
            self.sort = self.sort if self.sort in SORTS else "manual"
            self.due_sig = None
            self.undo = []
            self.last_written = None
            self.day = today()

            outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            self.overlay = Gtk.Overlay()  # the deadline picker opens on top of this
            self.overlay.add(outer)
            self.add(self.overlay)
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
            self.add_entry = Gtk.Entry(placeholder_text="Add a task…  @fri 5pm = deadline")
            self.add_entry.connect("activate", lambda _e: self.on_add())
            bar.pack_start(self.add_entry, True, True, 0)
            self.add_due = Gtk.Button()
            self.add_due.set_can_focus(False)
            self.add_due.get_style_context().add_class("due")
            self.add_due.connect("clicked", lambda b: self.open_due(
                b, self.new_due, self.new_every, self.set_new_due, refocus=self.add_entry))
            self.show_new_due()
            bar.pack_start(self.add_due, False, False, 0)
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
            text, due, every, prio, bad = split_spec(" ".join(self.add_entry.get_text().split()))
            if bad:
                self.say(f"{bad} is not a date I know: try @fri, @tomorrow 5pm, @20/10, @every mon")
                return
            if not text:
                return
            if not due:
                due, every = self.new_due, self.new_every
            self.snapshot()
            self.tasks.append(Task(text, added=today(), due=due, every=every, prio=prio or 0))
            self.add_entry.set_text("")
            self.set_new_due("", "")
            self.save(f"Added “{text}”" + (f" · due {due_long(due)}" if due else "")
                      + (f" · {rule_label(every)}" if every else ""))

        # ── deadlines ──
        def open_due(self, anchor, current, every, on_pick, refocus=None):
            def closed():
                self.popover = None
                if refocus:
                    refocus.grab_focus()
            # Deferred like EditableRow's save: picking rebuilds the list,
            # which holds the anchor of this very popover.
            self.popover = due_popover(self.overlay, anchor, current, every,
                                       lambda due, ev: GLib.idle_add(lambda: on_pick(due, ev) and False), closed)

        def set_new_due(self, due, every):
            self.new_due, self.new_every = due, (every if due else "")
            self.show_new_due()

        def show_new_due(self):
            ctx = self.add_due.get_style_context()
            if self.new_due:
                self.add_due.set_label(f"{ICON_DUE} {due_label(self.new_due)}" + (" ↻" if self.new_every else ""))
                self.add_due.set_tooltip_text(f"Deadline for the next task: {due_long(self.new_due)}"
                                              + (f" · {rule_label(self.new_every)}" if self.new_every else ""))
                ctx.add_class("due-set")
            else:
                self.add_due.set_label(ICON_DUE_ADD)
                self.add_due.set_tooltip_text("Deadline for the next task (or end it with @fri 5pm)")
                ctx.remove_class("due-set")

        def set_due(self, task, due, every):
            every = every if due else ""
            if (task.due, task.every) == (due, every):
                return
            self.snapshot()
            task.due, task.every = due, every
            self.save(f"Due {due_long(due)}" + (f", {rule_label(every)}" if every else "") + f": “{task.text}”"
                      if due else f"No deadline: “{task.text}”")

        def cycle_prio(self, task):
            self.snapshot()
            task.prio = (task.prio + 1) % 4
            self.save(f"{PRIO_NAMES[task.prio].capitalize()}: “{task.text}”")

        def cycle_sort(self):
            self.sort = SORTS[(SORTS.index(self.sort) + 1) % len(SORTS)]
            try:
                atomic_write(PANEL_STATE, json.dumps({"sort": self.sort}))
            except OSError:
                pass
            self.render()
            self.say(f"Remaining sorted by {self.sort}" + ("  (↑↓ to reorder)" if self.sort == "manual" else ""))

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
            nxt = set_task_done(self.tasks, task, done)
            msg = (f"Done: “{task.text}”" + (f" · next one due {due_long(nxt.due)}" if nxt else "")
                   if done else f"Back on the list: “{task.text}”")
            GLib.idle_add(lambda: self.save(msg) and False)

        def rename(self, task, text):
            """Typing ! / !! / !!! or an @deadline into an edit sets those too."""
            new, due, every, prio, bad = split_spec(text)
            if bad:
                self.say(f"{bad} is not a date I know: try @fri, @tomorrow 5pm, @20/10, @every mon")
                return
            if not new:
                return
            self.snapshot()
            task.text = new
            if due:
                task.due, task.every = due, every
            if prio is not None:
                task.prio = prio
            self.save("Edited")

        def delete(self, task):
            self.snapshot()
            self.tasks.remove(task)
            self.save(f"Deleted “{task.text}”  ·  Ctrl+Z to undo")

        def move(self, task, step):
            pending = self.shown_rest  # as listed under REMAINING (manual order)
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
            self.due_sig = [(due_label(t.due), due_level(t.due)) for t in self.tasks if t.due and not t.done]
            far = dt.datetime.max

            # Overdue and due in the next two days, soonest first, on top.
            horizon = now() + dt.timedelta(days=2)
            soon = sorted((t for t in pending if t.due and due_at(t.due) and due_at(t.due) <= horizon),
                          key=lambda t: (due_at(t.due), -t.prio))
            rest = [t for t in pending if t not in soon]
            if self.sort == "deadline":
                rest.sort(key=lambda t: (due_at(t.due) or far, -t.prio))
            elif self.sort == "priority":
                rest.sort(key=lambda t: (-t.prio, due_at(t.due) or far))
            self.shown_rest = rest

            if soon:
                self.body.pack_start(section_label(f"DUE SOON · {len(soon)}", "section-soon"), False, False, 0)
                self.body.pack_start(self._list(soon, lambda t: self._pending_row(t, False), ""), False, False, 0)
            sort = Gtk.Button(label=f"sort: {self.sort}")
            sort.set_can_focus(False)
            sort.get_style_context().add_class("sort")
            sort.set_tooltip_text("Order of the list below: manual (↑↓) › deadline › priority")
            sort.connect("clicked", lambda _b: self.cycle_sort())
            head = f"REMAINING · {len(rest)}" if soon else f"REMAINING · {len(pending)}"
            self.body.pack_start(section_head(head, button=sort), False, False, 0)
            self.body.pack_start(self._list(rest, lambda t: self._pending_row(t, self.sort == "manual"),
                                            "Nothing else left." if soon else "Nothing left. Add something above."),
                                 False, False, 0)
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

        def _prio_button(self, task):
            b = Gtk.Button(label="!" * max(1, task.prio))
            b.set_can_focus(False)
            b.set_valign(Gtk.Align.CENTER)
            b.set_relief(Gtk.ReliefStyle.NONE)
            for cls in ("prio", f"prio-{task.prio}"):
                b.get_style_context().add_class(cls)
            b.set_tooltip_text(f"{PRIO_NAMES[task.prio].capitalize()} · click to change (or type ! / !! / !!!)")
            b.connect("clicked", lambda _b: self.cycle_prio(task))
            return b

        def _pending_row(self, task, movable=True):
            row = EditableRow(self, task.text, lambda new: self.rename(task, new))
            row.box.pack_start(self._check(task), False, False, 0)
            row.box.pack_start(self._prio_button(task), False, False, 0)
            row.pack_text()
            row.box.pack_start(self._due_button(task), False, False, 0)
            age = task.age_days()
            if age:
                meta = Gtk.Label(label=f"{age}d")
                meta.set_tooltip_text(f"Added {task.added}, carried over {age} day{'s' if age != 1 else ''}")
                meta.get_style_context().add_class("meta")
                if age >= 3:
                    meta.get_style_context().add_class("meta-old")
                row.box.pack_start(meta, False, False, 0)
            if movable:
                row.box.pack_start(icon_button(ICON_UP, "Move up", lambda: self.move(task, -1)), False, False, 0)
                row.box.pack_start(icon_button(ICON_DOWN, "Move down", lambda: self.move(task, 1)), False, False, 0)
            row.box.pack_start(icon_button(ICON_EDIT, "Edit (or double-click)", row.start_edit), False, False, 0)
            row.box.pack_start(icon_button(ICON_DEL, "Delete", lambda: self.delete(task), True), False, False, 0)
            return row

        def _due_button(self, task):
            if not task.due:
                b = icon_button(ICON_DUE_ADD, "Set a deadline",
                                lambda: self.open_due(b, "", "", lambda d, e: self.set_due(task, d, e)))
                return b
            b = Gtk.Button(label=f"{ICON_DUE} {due_label(task.due)}" + (" ↻" if task.every else ""))
            b.set_can_focus(False)
            b.set_valign(Gtk.Align.CENTER)
            ctx = b.get_style_context()
            ctx.add_class("due")
            level = due_level(task.due)
            if level:
                ctx.add_class("due-overdue" if level == "overdue" else "due-soon")
            b.set_tooltip_text(f"Due {due_long(task.due)}" + (f" · {rule_label(task.every)}" if task.every else "")
                               + " · click to change")
            b.connect("clicked", lambda w: self.open_due(w, task.due, task.every,
                                                          lambda d, e: self.set_due(task, d, e)))
            return b

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
            if self.editing or self.popover:
                return  # do not yank the row out from under the cursor
            tasks_now = read_text(TASKS_FILE)
            log_now = read_day(today())["log"]
            if tasks_now != self.last_written or log_now != self.log:
                self.reload()
                self.say("Reloaded: changed outside the panel")

        def _tick(self):
            if self.editing or self.popover:
                return True
            if today() != self.day:
                self.day = today()
                self.undo.clear()
                self.reload()
                self.say("New day: yesterday's done tasks archived")
            else:
                # "in 25m", "overdue 2h": redraw when a deadline's label moves on
                sig = [(due_label(t.due), due_level(t.due)) for t in self.tasks if t.due and not t.done]
                if sig != self.due_sig:
                    self.render()
            self.show_new_due()
            return True

        def say(self, text):
            self.status.set_text(text)

        def say_counts(self):
            pending, done = split_buckets(self.tasks)
            levels = [due_level(t.due) for t in pending if t.due]
            due = "".join(f" · {levels.count(k)} {name}" for k, name in
                          (("overdue", "overdue"), ("soon", "due within a day")) if levels.count(k))
            self.say(f"{len(pending)} remaining{due} · {len(done)} done today  ·  "
                     "double-click to edit · Ctrl+Z undo · Esc close")

        def on_key(self, _w, event):
            ctrl = event.state & Gdk.ModifierType.CONTROL_MASK
            if self.popover and event.keyval == Gdk.KEY_Escape:
                self.popover.popdown()
                return True
            if self.editing or self.popover:
                return False  # the inline entry / the picker's widgets handle the rest
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
    elif cmd == "watch":                     # the bar: `status` on a timer, in one process
        import barwatch
        barwatch.run(cmd_status, float(args[1]) if len(args) > 1 else 2)
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
    elif cmd == "remind":
        cmd_remind()
    elif cmd == "deadlines":
        cmd_deadlines()
    elif cmd == "json":
        cmd_json()
    elif cmd == "op":
        cmd_op(args[1:])
    elif cmd == "day":
        cmd_day(args[1] if len(args) > 1 else "")
    elif cmd == "notify-due" and len(args) == 2:
        cmd_notify_due(args[1])
    else:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
