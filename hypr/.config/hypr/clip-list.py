#!/usr/bin/env python3
"""Clipboard history for the top bar's clipboard popup (ClipboardPopup.qml).

  clip-list.py [N]   JSON list of the newest N cliphist entries (default 150):
                     [{"id": "389", "text": "...", "image": "/path/to/thumb.png" | ""}]

Images are decoded once into ~/.cache/cliphist-thumbs/<id>.<ext> (cliphist ids
never repeat), and thumbnails of entries that are gone are deleted.

  clip-list.py delete ID   remove one entry
  clip-list.py wipe        remove everything
"""
import json
import re
import subprocess
import sys
from pathlib import Path

THUMBS = Path.home() / ".cache/cliphist-thumbs"
BINARY = re.compile(r"^\[\[ binary data .* (png|jpeg|jpg|gif|bmp|webp) (\d+)x(\d+) \]\]$")


def delete(cid):
    out = subprocess.run(["cliphist", "list"], capture_output=True).stdout
    for line in out.split(b"\n"):
        if line.split(b"\t", 1)[0] == cid.encode():
            subprocess.run(["cliphist", "delete"], input=line + b"\n")
            break


def main():
    if sys.argv[1:2] == ["delete"]:
        delete(sys.argv[2])
        return
    if sys.argv[1:2] == ["wipe"]:
        subprocess.run(["cliphist", "wipe"])
        return
    limit = int(sys.argv[1]) if len(sys.argv) > 1 else 150
    out = subprocess.run(["cliphist", "list"], capture_output=True).stdout.decode("utf-8", "replace")
    THUMBS.mkdir(parents=True, exist_ok=True)
    entries, keep = [], set()
    for line in out.splitlines()[:limit]:
        cid, _, preview = line.partition("\t")
        if not cid.isdigit():
            continue
        e = {"id": cid, "text": preview, "image": ""}
        m = BINARY.match(preview)
        if m:
            ext = "jpg" if m.group(1) == "jpeg" else m.group(1)
            thumb = THUMBS / f"{cid}.{ext}"
            if not thumb.exists():
                data = subprocess.run(["cliphist", "decode", cid], input=line.encode(),
                                      capture_output=True).stdout
                if data:
                    thumb.write_bytes(data)
            if thumb.exists():
                e["image"] = str(thumb)
                e["text"] = f"Image · {m.group(2)}×{m.group(3)}"
                keep.add(thumb.name)
        entries.append(e)
    for f in THUMBS.iterdir():
        if f.name not in keep:
            f.unlink(missing_ok=True)
    print(json.dumps(entries))


if __name__ == "__main__":
    main()
