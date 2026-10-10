#!/usr/bin/python3
"""The wallpaper list for the Quickshell wallpaper picker
(~/.config/quickshell/WallpaperPicker.qml, SUPER+W / SUPER+SHIFT+W).

    wallpaper-index.py desktop|lock --card WxH

prints one JSON object and exits:

    {"mode": ..., "current": <path>, "items": [
        {"path", "name", "bucket", "video", "card", "still"}, ...]}

sorted the way the picker shows them (colour buckets as a rainbow, personal
wallpapers before /usr/share/backgrounds, then by name).

  bucket  the colour filter: Red Orange Yellow Green Blue Purple Pink Mono —
          hue-weighting of the saturated pixels, the same classify() the old
          GTK picker (wallpaper-picker.py) used, cached in
          ~/.cache/wallpaper-thumbs/colours.json by mtime. Only NEW files are
          decoded, so a normal run takes a few ms.
  card    the card picture cropped to WxH, if already cached (else "")
  still   what to show until then: the image itself, or a video's poster
          frame if cached (else "")

Anything missing (cards at this size, video posters) is made AFTER the JSON
is printed, by a detached child, so the picker never waits for it: the next
open has them. GTK-free on purpose — this runs on every open and has to start
fast; wallpaper-picker.py stays as the old standalone picker.
"""

import colorsys
import hashlib
import json
import os
import re
import subprocess
import sys

HOME = os.path.expanduser("~")
HYPR = os.path.join(HOME, ".config/hypr")
SOURCES = (os.path.join(HOME, "Pictures/wallpapers"), "/usr/share/backgrounds")
STATE = os.path.join(HYPR, "wallpaper")
LOCK_CONF = os.path.join(HYPR, "hyprlock.conf")
CACHE = os.path.join(HOME, ".cache/wallpaper-thumbs")
CARDS = os.path.join(CACHE, "carousel")
INDEX = os.path.join(CACHE, "colours.json")

IMAGE_EXTS = (".png", ".jpg", ".jpeg", ".webp", ".bmp")
VIDEO_EXTS = (".mp4", ".webm", ".mkv", ".mov", ".gif")    # = set-wallpaper.sh is_video

COLOURS = ["Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Pink", "Mono"]
ORDER = {name: i for i, name in enumerate(COLOURS)}


def is_video(path):
    return path.lower().endswith(VIDEO_EXTS)


def wallpapers(lock):
    """Every image (and, for the desktop, video) in the sources, personal
    first; symlinks to one file (Ubuntu's greyscale default) only once."""
    sources, exts = (SOURCES[:1], IMAGE_EXTS) if lock else (SOURCES, IMAGE_EXTS + VIDEO_EXTS)
    seen, out = set(), []
    for d in sources:
        try:
            names = sorted(os.listdir(d), key=str.lower)
        except OSError:
            continue
        for f in names:
            p = os.path.join(d, f)
            if not f.lower().endswith(exts) or not os.path.isfile(p):
                continue
            real = os.path.realpath(p)
            if real not in seen:
                seen.add(real)
                out.append(p)
    return out


def current(lock):
    try:
        if not lock:
            with open(STATE) as f:
                return f.read().strip()
        with open(LOCK_CONF) as f:
            block = re.search(r"background\s*\{.*?\}", f.read(), re.S)
        line = block and re.search(r"^\s*path\s*=\s*(.+?)\s*$", block.group(0), re.M)
        return line.group(1) if line else ""
    except OSError:
        return ""


def key_for(path):
    st = os.stat(path)
    return hashlib.sha1(path.encode()).hexdigest()[:16], int(st.st_mtime)


# The cache names below are wallpaper-picker.py's, so both share one cache.
def poster_path(path):
    h, mtime = key_for(path)
    return os.path.join(CARDS, f"poster-{h}-{mtime}.png")


def card_path(path, w, h):
    k, mtime = key_for(path)
    return os.path.join(CARDS, f"card-{k}-{mtime}-{w}x{h}.png")


def make_poster(path):
    """A still for a video: a frame 1 s in (0 s for shorter clips)."""
    out = poster_path(path)
    if os.path.exists(out):
        return out
    os.makedirs(CARDS, exist_ok=True)
    tmp = f"{out}.{os.getpid()}.tmp.png"
    for seek in ("1", "0"):
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", seek, "-i", path,
                        "-frames:v", "1", "-vf", "scale=960:-2", tmp],
                       stdin=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)
        if os.path.exists(tmp):
            os.replace(tmp, out)
            return out
    return None


def open_still(path):
    from PIL import Image
    src = make_poster(path) if is_video(path) else path
    if not src:
        return None
    im = Image.open(src)
    try:
        im.draft("RGB", (1200, 1200))          # JPEG: decode at reduced size, fast
    except (AttributeError, ValueError):
        pass
    return im.convert("RGB")


def classify(im):
    """-> bucket. Hue histogram of the saturated pixels, each weighted by
    saturation × value; Mono when under 12 % of the picture is colourful."""
    small = im.copy()
    small.thumbnail((96, 96))
    weights = dict.fromkeys(COLOURS, 0.0)
    total = colourful = 0
    for r, g, b in small.getdata():
        total += 1
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        if s < 0.22 or v < 0.18:
            continue
        colourful += 1
        deg = h * 360
        if deg < 12 or deg >= 345:
            name = "Red"
        elif deg < 40:
            name = "Orange"
        elif deg < 68:
            name = "Yellow"
        elif deg < 165:
            name = "Green"
        elif deg < 255:
            name = "Blue"
        elif deg < 312:            # Ubuntu's aubergine (~305°) is purple, not pink
            name = "Purple"
        else:
            name = "Pink"
        weights[name] += s * v
    if not total or colourful / total < 0.12:
        return "Mono"
    return max(weights, key=weights.get)


def make_card(path, w, h):
    """The wallpaper cropped to cover w×h (the widest card plus its slant)."""
    from PIL import Image
    out = card_path(path, w, h)
    if os.path.exists(out):
        return
    im = open_still(path)
    if im is None:
        return
    scale = max(w / im.width, h / im.height)
    im = im.resize((max(w, round(im.width * scale)), max(h, round(im.height * scale))),
                   Image.LANCZOS)
    left, top = (im.width - w) // 2, (im.height - h) // 2
    os.makedirs(CARDS, exist_ok=True)
    tmp = f"{out}.{os.getpid()}.tmp.png"
    im.crop((left, top, left + w, top + h)).save(tmp)
    os.replace(tmp, out)


def bucket_of(path, index):
    _, mtime = key_for(path)
    hit = index.get(path)
    if hit and hit.get("mtime") == mtime:
        return hit["bucket"]
    try:
        im = open_still(path)
        bucket = classify(im) if im is not None else "Mono"
    except Exception as e:                      # noqa: BLE001 — one bad file
        print(f"wallpaper-index: {path}: {e}", file=sys.stderr)
        bucket = "Mono"
    index[path] = {"mtime": mtime, "bucket": bucket}
    return bucket


def main():
    args = sys.argv[1:]
    lock = "lock" in args
    w = h = 0
    if "--card" in args:
        try:
            w, h = (int(x) for x in args[args.index("--card") + 1].split("x"))
        except (IndexError, ValueError):
            w = h = 0
    if w < 200 or h < 100:                      # a window not mapped yet; never cache
        w = h = 0                               # thumbnails that small (they blur)

    try:
        with open(INDEX) as f:
            index = json.load(f)
    except (OSError, ValueError):
        index = {}
    before = len(index)

    items, missing = [], []
    for p in wallpapers(lock):
        try:
            bucket = bucket_of(p, index)
        except OSError:
            continue
        video = is_video(p)
        card = card_path(p, w, h) if w else ""
        if card and not os.path.exists(card):
            missing.append(p)
            card = ""
        still = p
        if video:
            still = poster_path(p)
            if not os.path.exists(still):
                still = ""
        items.append({"path": p, "name": os.path.splitext(os.path.basename(p))[0],
                      "bucket": bucket, "video": video, "card": card, "still": still})

    if len(index) != before:
        os.makedirs(CACHE, exist_ok=True)
        with open(INDEX + ".tmp", "w") as f:
            json.dump(index, f)
        os.replace(INDEX + ".tmp", INDEX)

    items.sort(key=lambda e: (ORDER.get(e["bucket"], 9),
                              not e["path"].startswith(SOURCES[0]), e["name"].lower()))
    sys.stdout.write(json.dumps({"mode": "lock" if lock else "desktop",
                                 "current": current(lock), "items": items}))
    sys.stdout.flush()

    if missing and os.fork() == 0:              # cards for next time, detached
        os.setsid()
        devnull = os.open(os.devnull, os.O_RDWR)
        for fd in (0, 1, 2):
            os.dup2(devnull, fd)
        for p in missing:
            try:
                make_card(p, w, h)
            except Exception:                   # noqa: BLE001
                pass
        os._exit(0)


if __name__ == "__main__":
    main()
