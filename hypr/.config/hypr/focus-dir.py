#!/usr/bin/python3
"""SUPER+arrows / SUPER+HJKL: movefocus that also reaches floating windows.

    focus-dir.py l|r|u|d

Hyprland's movefocus only looks among windows of the active one's own kind
(CCompositor::getWindowInDirection: a tiled window only finds tiled ones, a
floating one only floating ones), so the floating popups (screenshot-save,
tasks, notif-center, network panel, media menu...) could only be reached by
hovering them. This picks the nearest window in that direction of EITHER
kind:

  * same kind: from a tiled window Hyprland's own pick (plain movefocus, so
    tiled-to-tiled moves are exactly as before); from a floating one,
    Hyprland's floating rule, re-done here (smallest angle, then distance).
  * other kind: from a tiled window, floats ahead of it (same floating rule);
    a float sitting on top of it (a centred popup over the only window)
    counts in every direction that has no tiled neighbour. From a float,
    the tiled window just past its edge in that direction.
  * both, from a tiled window: the one whose centre is nearer along that
    axis. From a float, another float first (they sit on top), then tiled.
  * neither, or the active window is fullscreen: plain movefocus (monitor
    fallback etc.).

SUPER+SHIFT+arrows (movewindow) are separate binds and untouched.
"""

import json
import math
import os
import socket
import sys

SOCK = os.path.join(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"), "hypr",
                    os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", ""), ".socket.sock")
VEC = {"l": (-1, 0), "r": (1, 0), "u": (0, -1), "d": (0, 1)}
STICK = 20      # tiled neighbours are a gap + two borders apart (8 px here)


def ipc(cmd):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(SOCK)
    s.sendall(cmd.encode())
    out = b""
    while chunk := s.recv(65536):
        out += chunk
    s.close()
    return out.decode()


def movefocus(d):
    ipc(f"dispatch movefocus {d}")


def box(c):
    (x, y), (w, h) = c["at"], c["size"]
    return x, y, w, h


def mid(c):
    x, y, w, h = box(c)
    return x + w / 2, y + h / 2


def ahead(d, a, b):
    """Distance from centre a to centre b along d (> 0: b is that way)."""
    vx, vy = VEC[d]
    return (b[0] - a[0]) * vx + (b[1] - a[1]) * vy


def by_angle(d, origin, cands):
    """Hyprland's floating movefocus: within 0.3 pi of the direction, the
    nearest; failing that, the smallest angle. Nothing past 90 degrees."""
    vx, vy = VEC[d]
    best, best_ang, best_dist = None, 2 * math.pi, -1
    for c in cands:
        m = mid(c)
        dx, dy = m[0] - origin[0], m[1] - origin[1]
        dist = math.hypot(dx, dy)
        if dist == 0:
            continue
        ang = math.acos(max(-1, min(1, (dx * vx + dy * vy) / dist)))
        if ang > math.pi / 2:
            continue
        th = 0.3 * math.pi
        if (best_ang < th and dist < best_dist and ang < th) or (ang < best_ang and best_ang > th) or best is None:
            best, best_ang, best_dist = c, ang, dist
    return best


def tiled_neighbour(d, a, tiled):
    """Whether movefocus will find a tiled window that way, and how far its
    centre is: the windows whose facing edge touches this one's."""
    ax, ay, aw, ah = box(a)
    near = None
    for c in tiled:
        x, y, w, h = box(c)
        if d in "lr":
            touch = abs((ax - (x + w)) if d == "l" else (x - (ax + aw))) < STICK
            overlap = min(ay + ah, y + h) - max(ay, y) > 0
        else:
            touch = abs((ay - (y + h)) if d == "u" else (y - (ay + ah))) < STICK
            overlap = min(ax + aw, x + w) - max(ax, x) > 0
        if touch and overlap:
            dist = ahead(d, mid(a), mid(c))
            near = dist if near is None else min(near, dist)
    return near


def tiled_past_edge(d, a, tiled):
    """From a float: the tiled window just past its edge that way (at the
    middle of that edge), else the nearest tiled one ahead by angle."""
    x, y, w, h = box(a)
    px, py = {"l": (x - 8, y + h / 2), "r": (x + w + 8, y + h / 2),
              "u": (x + w / 2, y - 8), "d": (x + w / 2, y + h + 8)}[d]
    for c in sorted(tiled, key=lambda c: c["focusHistoryID"]):
        cx, cy, cw, ch = box(c)
        if cx <= px < cx + cw and cy <= py < cy + ch:
            return c
    return by_angle(d, mid(a), tiled)


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else ""
    if d not in VEC:
        sys.exit("usage: focus-dir.py l|r|u|d")
    try:
        a = json.loads(ipc("j/activewindow"))
        clients = json.loads(ipc("j/clients"))
    except (OSError, ValueError):
        return movefocus(d)
    if not a or not a.get("address") or a.get("fullscreen"):
        return movefocus(d)

    ws, mon = a["workspace"]["id"], a["monitor"]
    others = [c for c in clients
              if c["address"] != a["address"] and c["mapped"] and not c["hidden"]
              and c["monitor"] == mon and (c["workspace"]["id"] == ws or c["pinned"])
              and (c["class"] or c["title"])]     # skip XWayland drag helpers (no_focus rule)
    floats = [c for c in others if c["floating"]]
    tiled = [c for c in others if not c["floating"]]
    me = mid(a)

    if not a["floating"]:
        if not floats:
            return movefocus(d)                   # nothing new to reach: exactly as before
        same = tiled_neighbour(d, a, tiled)
        other = by_angle(d, me, [f for f in floats if ahead(d, me, mid(f)) > 0])
        if other is None and same is None:
            ax, ay, aw, ah = box(a)
            over = [f for f in floats if ax <= mid(f)[0] < ax + aw and ay <= mid(f)[1] < ay + ah]
            other = min(over, key=lambda c: c["focusHistoryID"], default=None)
        if other is not None and (same is None or ahead(d, me, mid(other)) < same):
            return ipc(f"dispatch focuswindow address:{other['address']}")
        return movefocus(d)

    pick = by_angle(d, me, floats) or tiled_past_edge(d, a, tiled)
    if pick is None:
        return movefocus(d)
    ipc(f"dispatch focuswindow address:{pick['address']}")


if __name__ == "__main__":
    main()
