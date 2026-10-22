#!/usr/bin/python3
"""The wallpaper list for the Quickshell wallpaper picker
(~/.config/quickshell/WallpaperPicker.qml, SUPER+W / SUPER+SHIFT+W).

    wallpaper-index.py desktop|lock --card WxH

prints one JSON object and exits:

    {"mode": ..., "current": <path>, "items": [
        {"path", "name", "bucket", "accent", "video", "card", "still"}, ...]}

sorted the way the picker shows them (colour buckets as a rainbow, personal
wallpapers before /usr/share/backgrounds, then by name).

  bucket  the colour filter: Red Orange Yellow Green Blue Purple Pink Mono —
          see classify(). Cached in ~/.cache/wallpaper-thumbs/colours.json by
          mtime (and CLASSIFIER version). Only NEW files are decoded, so a
          normal run takes a few ms.
  accent  Mono only: the wallpaper's own grey ("#rrggbb"), the accent a
          black-and-white wallpaper sets; "" for the colour buckets (they set
          the theme's colour for their role)
  card    the card picture cropped to WxH, if already cached (else "")
  still   what to show until then: the image itself, or a video's poster
          frame if cached (else "")

Anything missing (cards at this size, video posters) is made AFTER the JSON
is printed, by a detached child, so the picker never waits for it: the next
open has them. GTK-free on purpose — this runs on every open and has to start
fast; wallpaper-picker.py stays as the old standalone picker.
"""

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


# Bump when classify() changes: cached buckets from an older version are
# recomputed (once) on the next run.
CLASSIFIER = 2

# Where each bucket STARTS on the OKLCH hue circle (Pink wraps round to Red).
# Perceptual hue, not HSV: in HSV a lavender sky (~245°) and pure blue (240°)
# are neighbours and violet-ish night skies all landed in Blue. Set from
# reference colours: crimson 20 / red 29 | orangered 35, dark orange 58 |
# gold 95 | yellow-green 127 | teal and cyan 195 | blue 264, slate blue 286 |
# blue-violet 301 | magenta 328 / deep pink 357 | pink and sakura 6-7.
HUE_STARTS = (("Red", 14), ("Orange", 34), ("Yellow", 80), ("Green", 118),
              ("Blue", 175), ("Purple", 280), ("Pink", 333))
BLUE_DISCOUNT = 0.5


def oklab(rgb):
    """sRGB floats 0-1 (…×3 array) -> OKLab (…×3)."""
    import numpy as np
    lin = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    lms = np.cbrt(lin @ np.array([[0.4122214708, 0.5363325363, 0.0514459929],
                                  [0.2119034982, 0.6806995451, 0.1073969566],
                                  [0.0883024619, 0.2817188376, 0.6299787005]]).T)
    return lms @ np.array([[0.2104542553, 0.7936177850, -0.0040720468],
                           [1.9779984951, -2.4285922050, 0.4505937099],
                           [0.0259040371, 0.7827717662, -0.8086757162]]).T


def oklab_hex(lab):
    import numpy as np
    lms = np.asarray(lab) @ np.array([[1, 0.3963377774, 0.2158037573],
                                      [1, -0.1055613458, -0.0638541728],
                                      [1, -0.0894841775, -1.2914855480]]).T
    lin = (lms ** 3) @ np.array([[4.0767416621, -3.3077115913, 0.2309699292],
                                 [-1.2684380046, 2.6097574011, -0.3413193965],
                                 [-0.0041960863, -0.7034186147, 1.7076147010]]).T
    lin = np.clip(lin, 0, 1)
    srgb = np.where(lin <= 0.0031308, lin * 12.92, 1.055 * lin ** (1 / 2.4) - 0.055)
    return "#" + "".join(f"{round(float(c) * 255):02x}" for c in srgb)


def mono_accent(L, A, B):
    """A black-and-white wallpaper's own grey, as an accent: the lightness of
    its light tones (85th percentile, so a white subject on black counts),
    kept within what reads as an accent on the dark desktop — a near-black
    one would vanish — and the faint warm / cool cast of those tones, capped
    so it stays a grey."""
    import numpy as np
    lum = float(np.percentile(L, 85))
    light = L >= np.percentile(L, 50)
    a, b = float(A[light].mean()), float(B[light].mean())
    c = (a * a + b * b) ** 0.5
    if c > 0.02:
        a, b = a * 0.02 / c, b * 0.02 / c
    return oklab_hex((min(max(lum, 0.72), 0.93), a, b))


def classify(im):
    """-> (bucket, accent). The colour a person would call the picture's —
    its vivid colours, not its biggest area:

      Mono when under 12 % of the picture is colourful (HSV s ≥ .22, v ≥ .18),
      and then `accent` is the picture's own grey (mono_accent);
      else every colourful pixel (OKLCH chroma ≥ .04, lightness ≥ .25) votes
      for the bucket of its hue with chroma² — so a vivid subject outweighs a
      wide dull background — and a little more near the centre, where the
      subject usually is. Blue's total is halved: sky, sea and night fill
      the background of half the shelf, and blue then out-voted the pink
      blossoms / orange sunsets / red fighters the picture is actually of.
      Dark pixels in the pink-red overlap (hue < 14, lightness < .5) count as
      red: crimson leaves vs. sakura are told apart by lightness, not hue."""
    import numpy as np
    small = im.copy()
    small.thumbnail((128, 128))
    rgb = np.asarray(small, dtype=np.float32) / 255
    mx, mn = rgb.max(-1), rgb.min(-1)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    lab = oklab(rgb)
    L, A, B = lab[..., 0], lab[..., 1], lab[..., 2]
    if not L.size or ((sat >= 0.22) & (mx >= 0.18)).mean() < 0.11:
        return "Mono", mono_accent(L, A, B)
    C = np.hypot(A, B)
    H = np.degrees(np.arctan2(B, A)) % 360
    bucket = np.full(H.shape, len(HUE_STARTS) - 1)                 # Pink
    for i in range(len(HUE_STARTS) - 1):
        bucket[(H >= HUE_STARTS[i][1]) & (H < HUE_STARTS[i + 1][1])] = i
    bucket[(H < HUE_STARTS[0][1]) & (L < 0.5)] = 0                  # dark pink = red
    h, w = H.shape
    yy, xx = np.mgrid[0:h, 0:w]
    centre = 1 - 0.3 * (((xx - w / 2) / (w / 2)) ** 2 + ((yy - h / 2) / (h / 2)) ** 2)
    weight = C ** 2 * centre * ((C >= 0.04) & (L >= 0.25))
    votes = [float(weight[bucket == i].sum()) for i in range(len(HUE_STARTS))]
    votes[4] *= BLUE_DISCOUNT
    return HUE_STARTS[int(np.argmax(votes))][0], ""


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
    """-> (bucket, accent), cached by mtime and classifier version."""
    _, mtime = key_for(path)
    hit = index.get(path)
    if hit and hit.get("mtime") == mtime and hit.get("v") == CLASSIFIER:
        return hit["bucket"], hit.get("accent", "")
    try:
        im = open_still(path)
        bucket, accent = classify(im) if im is not None else ("Mono", "")
    except Exception as e:                      # noqa: BLE001 — one bad file
        print(f"wallpaper-index: {path}: {e}", file=sys.stderr)
        bucket, accent = "Mono", ""
    index[path] = {"mtime": mtime, "v": CLASSIFIER, "bucket": bucket, "accent": accent}
    return bucket, accent


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
    before = dict(index)          # (re)classified entries are new objects

    items, missing = [], []
    for p in wallpapers(lock):
        try:
            bucket, accent = bucket_of(p, index)
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
                      "bucket": bucket, "accent": accent, "video": video,
                      "card": card, "still": still})

    if index.keys() != before.keys() or any(index[k] is not before[k] for k in index):
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
