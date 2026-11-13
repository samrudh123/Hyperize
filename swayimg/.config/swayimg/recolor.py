#!/usr/bin/python3
"""Print an image recoloured the way zathura recolours PDF pages.

    recolor.py IMAGE          -> PNG bytes on stdout
    recolor.py --plain IMAGE  -> the file unchanged (see drain())

swayimg has no colour filters, so `w` in swayimg (see ./shell) makes the
viewer load images through this script instead of straight from disk.

The colours come from ~/.config/zathura/zathurarc — the file set-accent.sh
renders for the current theme/accent — so images match PDFs: recolor-
lightcolor/-darkcolor, keephue. White becomes the page colour, black becomes
the text colour, and with keephue each pixel keeps its hue (a red stays red,
only its lightness flips). Same maths as the yazi PDF preview and the
VS Code / Zen viewer.

Results are cached in ~/.cache/swayimg-recolor, keyed by the image (path,
size, mtime) and the zathurarc colours, so a theme/accent change re-renders.
Anything PIL can't open (svg, raw, some heif/jxl) or animated images are
printed unchanged.
"""
import hashlib
import os
import re
import shlex
import shutil
import sys
import time

LUMA = (0.2126, 0.7152, 0.0722)
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"),
                     "swayimg-recolor")
KEEP_DAYS = 7


def zathurarc():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    opts = {}
    try:
        lines = open(os.path.join(base, "zathura", "zathurarc")).read().splitlines()
    except OSError:
        return opts
    for line in lines:
        try:
            w = shlex.split(line, comments=True)
        except ValueError:
            continue
        if len(w) >= 2 and w[0] == "set":
            opts[w[1]] = w[2] if len(w) > 2 else "true"
    return opts


def rgb(value, default):
    s = (value or "").strip()
    m = re.fullmatch(r"#?([0-9a-fA-F]{6})", s)
    if m:
        return tuple(int(m.group(1)[i:i + 2], 16) / 255 for i in (0, 2, 4))
    m = re.fullmatch(r"rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+).*\)", s)
    if m:
        return tuple(int(x) / 255 for x in m.groups())
    return default


def passthrough(path):
    with open(path, "rb") as f:
        shutil.copyfileobj(f, sys.stdout.buffer)
    drain()


def drain():
    """Stay alive until swayimg has read everything we wrote.

    swayimg (4.7, shellcmd.c) reads exec:// output 4 KiB per poll() and stops
    reading stdout the moment it sees POLLHUP -- whatever is still in the
    pipe when we exit is thrown away, so big images arrived cut off
    ("Premature end of JPEG file", the lower part drawn grey). FIONREAD on
    our end of the pipe says how much it hasn't read yet."""
    import array
    import fcntl
    import stat
    import termios
    try:
        sys.stdout.buffer.flush()
        if not stat.S_ISFIFO(os.fstat(1).st_mode):
            return
        left = array.array("i", [0])
        deadline = time.monotonic() + 10       # swayimg's own exec timeout
        while time.monotonic() < deadline:
            fcntl.ioctl(1, termios.FIONREAD, left, True)
            if left[0] == 0:
                return
            time.sleep(0.002)
    except OSError:
        pass


def prune():
    # once a day: drop cache files nobody looked at for a week
    stamp = os.path.join(CACHE, ".pruned")
    try:
        if time.time() - os.path.getmtime(stamp) < 86400:
            return
    except OSError:
        pass
    cutoff = time.time() - KEEP_DAYS * 86400
    for e in os.scandir(CACHE):
        try:
            if e.name.endswith(".png") and e.stat().st_atime < cutoff:
                os.unlink(e.path)
        except OSError:
            pass
    open(stamp, "w").close()


def main(path):
    opt = zathurarc()
    light = rgb(opt.get("recolor-lightcolor"), (0, 0, 0))   # zathura's defaults
    dark = rgb(opt.get("recolor-darkcolor"), (1, 1, 1))
    keephue = opt.get("recolor-keephue") == "true"

    st = os.stat(path)
    key = hashlib.sha1(repr((os.path.realpath(path), st.st_size, st.st_mtime_ns,
                             light, dark, keephue)).encode()).hexdigest()
    out = os.path.join(CACHE, key + ".png")
    if os.path.exists(out):
        os.utime(out)          # keep it fresh for prune()
        return passthrough(out)

    import numpy as np
    from PIL import Image, ImageOps

    try:
        im = Image.open(path)
        if getattr(im, "n_frames", 1) > 1:       # animated: leave it moving
            return passthrough(path)
        im = ImageOps.exif_transpose(im)
    except Exception:
        return passthrough(path)

    alpha = None
    if im.mode in ("RGBA", "LA", "PA") or "transparency" in im.info:
        alpha = im.convert("RGBA").getchannel("A")   # transparency stays as is
    img = np.asarray(im.convert("RGB"), dtype=np.float32) / 255

    light = np.array(light, np.float32)
    dark = np.array(dark, np.float32)
    span = light - dark
    lum = (img @ np.array(LUMA, np.float32))[..., None]
    if keephue:
        img = img + lum * (span - 1) + dark   # same lightness shift, hue kept
    else:
        img = lum * span + dark
    img = (np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8)

    res = Image.fromarray(img, "RGB")
    if alpha is not None:
        res.putalpha(alpha)
    os.makedirs(CACHE, exist_ok=True)
    tmp = f"{out}.{os.getpid()}.tmp"
    res.save(tmp, "PNG", compress_level=1)
    os.replace(tmp, out)
    passthrough(out)
    prune()


if __name__ == "__main__":
    if sys.argv[1] == "--plain":                  # recolour off: the file as is
        try:
            passthrough(sys.argv[2])
        except BrokenPipeError:
            pass
        sys.exit()
    try:
        main(sys.argv[1])
    except BrokenPipeError:
        pass
    except Exception:
        # never leave the viewer with nothing to show
        passthrough(sys.argv[1])
