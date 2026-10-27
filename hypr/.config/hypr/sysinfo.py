#!/usr/bin/python3
"""Numbers for the top bar's system popups (Quickshell SysPopup.qml).

    sysinfo.py watch cpu  [SEC]   processes by CPU use, a JSON line every SEC (1.5)
    sysinfo.py watch mem  [SEC]   programs by memory, a JSON line every SEC (2)
    sysinfo.py watch temp [SEC]   temperature sensors + fans, every SEC (2)
    sysinfo.py battery            the battery's sysfs details, once

Runs only while a popup is open (the popup starts and stops it). Stdlib only,
straight from /proc and /sys.

CPU: like top — each process's utime+stime between two samples, as a percent
of ONE core (so a busy multi-threaded process can pass 100 %); the first line
comes after one interval.

MEMORY: grouped by program — the executable's basename (/proc/PID/exe), so a
browser's or Electron app's many processes count as one; the comm name when
exe can't be read (other users' processes). Each process counts its PSS
(proportional set size, /proc/PID/smaps_rollup: shared pages split between
the processes sharing them, so the sums don't double-count), RSS when PSS
can't be read.
"""

import glob
import json
import os
import pwd
import re
import sys
import time

CLK = os.sysconf("SC_CLK_TCK")
NCPU = os.cpu_count() or 1


def read(path, default=""):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return default


def pids():
    return [int(p) for p in os.listdir("/proc") if p.isdigit()]


def stat(pid):
    """-> (comm, utime+stime ticks, uid) or None"""
    s = read(f"/proc/{pid}/stat")
    if not s:
        return None
    i, j = s.find("("), s.rfind(")")
    comm = s[i + 1:j]
    f = s[j + 2:].split()
    try:
        ticks = int(f[11]) + int(f[12])
    except (IndexError, ValueError):
        return None
    try:
        uid = os.stat(f"/proc/{pid}").st_uid
    except OSError:
        uid = -1
    return comm, ticks, uid


_users = {}


def user(uid):
    if uid not in _users:
        try:
            _users[uid] = pwd.getpwuid(uid).pw_name
        except KeyError:
            _users[uid] = str(uid)
    return _users[uid]


def cmdline_name(pid, comm):
    """a friendlier name than the 15-char comm when the command line has one"""
    exe = ""
    try:
        exe = os.path.basename(os.readlink(f"/proc/{pid}/exe")).replace(" (deleted)", "")
    except OSError:
        pass
    if exe and comm.startswith(exe[:15]) and len(exe) > len(comm):
        return exe
    return comm


def cpu_lines(interval):
    prev, prev_t = {}, None
    while True:
        now_t = time.monotonic()
        cur = {}
        for p in pids():
            st = stat(p)
            if st:
                cur[p] = st
        if prev_t is not None:
            dt = now_t - prev_t
            rows = []
            for p, (comm, ticks, uid) in cur.items():
                if p in prev and prev[p][0] == comm:
                    pct = (ticks - prev[p][1]) / CLK / dt * 100
                    if pct > 0.05:
                        rows.append((pct, p, comm, uid))
            rows.sort(reverse=True)
            out = [{"pid": p, "name": cmdline_name(p, c), "pct": round(v, 1), "user": user(u)}
                   for v, p, c, u in rows[:15]]
            print(json.dumps({"procs": out, "count": len(cur), "ncpu": NCPU}), flush=True)
        prev, prev_t = cur, now_t
        time.sleep(interval)


def mem_kib(pid):
    """-> (kiB, "pss"|"rss")"""
    roll = read(f"/proc/{pid}/smaps_rollup")
    for line in roll.splitlines():
        if line.startswith("Pss:"):
            return int(line.split()[1]), "pss"
    statm = read(f"/proc/{pid}/statm").split()
    if len(statm) > 1:
        return int(statm[1]) * (os.sysconf("SC_PAGE_SIZE") // 1024), "rss"
    return 0, "rss"


def program(pid, comm):
    try:
        exe = os.path.basename(os.readlink(f"/proc/{pid}/exe")).replace(" (deleted)", "")
        # a version-numbered binary (e.g. "2.1.311") says nothing: use comm
        if exe and not exe.replace(".", "").isdigit():
            return re.sub(r"^(python\d|perl\d|ruby\d?)\.\d+$", r"\1", exe)   # python3.14 -> python3
    except OSError:
        pass
    return comm


def mem_lines(interval):
    while True:
        groups = {}
        for p in pids():
            st = stat(p)
            if not st:
                continue
            kib, how = mem_kib(p)
            if kib <= 0:
                continue
            name = program(p, st[0])
            g = groups.setdefault(name, {"name": name, "kib": 0, "procs": 0, "rss": False, "user": user(st[2])})
            g["kib"] += kib
            g["procs"] += 1
            g["rss"] |= how == "rss"
        rows = sorted(groups.values(), key=lambda g: -g["kib"])[:15]
        m = {}
        for line in read("/proc/meminfo").splitlines():
            k, _, v = line.partition(":")
            if v.split():
                m[k] = int(v.split()[0])
        print(json.dumps({"programs": rows, "meminfo": {k: m.get(k, 0) for k in (
            "MemTotal", "MemAvailable", "Cached", "Buffers", "SwapTotal", "SwapFree", "Shmem")}}), flush=True)
        time.sleep(interval)


ZONE_NAMES = {"x86_pkg_temp": None, "TCPU": "CPU (ACPI)", "TCPU_PCI": "CPU PCI", "SEN1": "Board sensor 1",
              "SEN2": "Board sensor 2", "SEN6": "Board sensor 6", "INT3400 Thermal": None}


def temp_lines(interval):
    while True:
        sensors, fans = [], []
        for h in sorted(glob.glob("/sys/class/hwmon/hwmon*")):
            chip = read(h + "/name").strip()
            group = ("CPU" if chip == "coretemp" else "Storage" if chip.startswith("nvme")
                     else "Wi-Fi" if chip.startswith("iwlwifi") else None)
            for t in sorted(glob.glob(h + "/temp*_input"), key=lambda x: int(x.split("temp")[-1].split("_")[0])):
                base = t[:-6]
                try:
                    c = int(read(t, "0").strip()) / 1000
                except ValueError:
                    continue
                if group is None or c <= 0:
                    continue
                label = read(base + "_label").strip() or chip
                if chip.startswith("nvme"):
                    label = "SSD " + label.lower()
                elif chip.startswith("iwlwifi"):
                    label = "Wi-Fi card"
                try:
                    crit = int(read(base + "_crit", "0").strip()) / 1000
                except ValueError:
                    crit = 0
                sensors.append({"group": group, "label": label.replace("Package id 0", "Package"),
                                "c": round(c, 1), "crit": crit})
            for fpath in glob.glob(h + "/fan*_input"):
                try:
                    rpm = int(read(fpath, "0").strip())
                except ValueError:
                    continue
                fans.append({"label": read(fpath[:-6] + "_label").strip() or chip + " fan", "rpm": rpm})
        for z in sorted(glob.glob("/sys/class/thermal/thermal_zone*"), key=lambda x: int(x.rsplit("e", 1)[-1])):
            typ = read(z + "/type").strip()
            name = ZONE_NAMES.get(typ, "" if typ == "acpitz" else False)
            if name is None or name is False:
                continue                             # duplicate of coretemp / Wi-Fi, or a dummy
            try:
                c = int(read(z + "/temp", "0").strip()) / 1000
            except ValueError:
                continue
            if c <= 0:
                continue
            sensors.append({"group": "Board", "label": name or "ACPI zone " + z.rsplit("e", 1)[-1],
                            "c": round(c, 1), "crit": 0})
        print(json.dumps({"sensors": sensors, "fans": fans}), flush=True)
        time.sleep(interval)


def battery():
    b = next(iter(sorted(glob.glob("/sys/class/power_supply/BAT*"))), "")
    if not b:
        return print(json.dumps({}))
    g = lambda k: read(f"{b}/{k}").strip()
    num = lambda k: int(g(k)) if g(k).lstrip("-").isdigit() else 0
    full, design = num("energy_full") or num("charge_full"), num("energy_full_design") or num("charge_full_design")
    print(json.dumps({"cycles": num("cycle_count"), "health": round(100 * full / design) if design else 0,
                      "fullWh": round(full / 1e6, 1), "designWh": round(design / 1e6, 1),
                      "voltage": round(num("voltage_now") / 1e6, 2), "technology": g("technology"),
                      "maker": g("manufacturer"), "model": g("model_name"), "status": g("status")}))


def main(argv):
    if not argv:
        sys.exit(__doc__)
    if argv[0] == "battery":
        return battery()
    if argv[0] == "watch" and len(argv) > 1:
        kind = argv[1]
        interval = float(argv[2]) if len(argv) > 2 else (1.5 if kind == "cpu" else 2.0)
        fn = {"cpu": cpu_lines, "mem": mem_lines, "temp": temp_lines}.get(kind)
        if fn:
            try:
                return fn(interval)
            except (KeyboardInterrupt, BrokenPipeError):
                return
    sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
