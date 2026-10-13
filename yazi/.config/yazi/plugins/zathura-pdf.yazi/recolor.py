#!/usr/bin/python3
"""Make one rendered PDF page look like zathura (yazi's preview pane).

    recolor.py IN.png OUT.jpg [QUALITY]

Reads ~/.config/zathura/zathurarc — the file set-accent.sh renders in the
current theme — and applies its recolour (recolor, recolor-keephue,
recolor-lightcolor, recolor-darkcolor) with the same colour matrix as the
VS Code viewer, then frames the page in default-bg like zathura's window.
IN is deleted afterwards.
"""
import os
import re
import shlex
import sys

import numpy as np
from PIL import Image

LUMA = np.array([0.2126, 0.7152, 0.0722])


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
        return np.array([int(m.group(1)[i:i + 2], 16) for i in (0, 2, 4)]) / 255
    m = re.fullmatch(r"rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+).*\)", s)
    if m:
        return np.array([int(x) for x in m.groups()]) / 255
    return np.array(default, float)


def main(src, dst, quality=75):
    opt = zathurarc()
    img = np.asarray(Image.open(src).convert("RGB"), dtype=np.float32) / 255

    if opt.get("recolor") == "true":
        # zathura's defaults: light parts -> black, dark parts -> white
        light = rgb(opt.get("recolor-lightcolor"), (0, 0, 0))
        dark = rgb(opt.get("recolor-darkcolor"), (1, 1, 1))
        span = light - dark
        lum = (img @ LUMA)[..., None]
        if opt.get("recolor-keephue") == "true":
            # same lightness shift, each channel keeps its offset from grey
            img = img + lum * (span - 1) + dark
        else:
            img = lum * span + dark
        img = np.clip(img, 0, 1)

    page = Image.fromarray((img * 255 + 0.5).astype(np.uint8))
    bg = tuple(int(c * 255 + 0.5) for c in rgb(opt.get("default-bg"), (0, 0, 0)))
    pad = max(8, round(max(page.size) * 0.03))
    framed = Image.new("RGB", (page.width + 2 * pad, page.height + 2 * pad), bg)
    framed.paste(page, (pad, pad))
    framed.save(dst, "JPEG", quality=int(quality))
    os.unlink(src)


if __name__ == "__main__":
    main(*sys.argv[1:4])
