#!/usr/bin/python3
"""Lyrics for the music panel (Quickshell MediaPopup.qml), from lrclib.net.

    lyrics.py ARTIST TITLE DURATION_S [ALBUM]

Prints one JSON object:
    {"synced": [[seconds, "line"], …], "plain": "…"}   (either may be empty)
    {"none": true}                                       nothing found
    {"error": "…"}                                       offline etc. (not cached)

/api/get (exact artist + title + duration ±2 s) first, then /api/search
with a cleaned-up title. Hits and misses are cached in ~/.cache/lyrics/
(misses for a day, so a new upload is picked up eventually).
"""

import hashlib
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

API = "https://lrclib.net/api"
UA = "rice-music-panel/1.0 (Quickshell; https://github.com/samrudh123/Hyperize)"
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "lyrics")
MISS_TTL = 24 * 3600


def fetch(path, params):
    url = API + path + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Lrclib-Client": UA})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=8) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            if e.code in (502, 503, 504) and attempt < 2:      # lrclib is often briefly busy
                time.sleep(0.8 * (attempt + 1))
                continue
            raise


def clean_title(t):
    # "Song (feat. X)", "Song - Remastered 2011", "Song [Official Video]"
    t = re.sub(r"\s*[\(\[][^)\]]*(feat|ft\.|official|video|audio|lyric|remaster|live|version|mv)[^)\]]*[\)\]]",
               "", t, flags=re.I)
    t = re.sub(r"\s+-\s+.*(remaster|version|edit|mix|live).*$", "", t, flags=re.I)
    return t.strip()


def clean_artist(a):
    a = re.sub(r"\s*-\s*Topic$", "", a)                  # YouTube "Artist - Topic"
    return re.split(r"\s*(?:,|&| feat\.? | ft\.? | x )\s*", a, maxsplit=1, flags=re.I)[0].strip()


def parse_lrc(text):
    out = []
    for line in (text or "").splitlines():
        stamps = re.findall(r"\[(\d+):(\d+(?:\.\d+)?)\]", line)
        words = re.sub(r"\[[^\]]*\]", "", line).strip()
        for m, s in stamps:
            out.append([round(int(m) * 60 + float(s), 2), words])
    out.sort(key=lambda x: x[0])
    return out


def usable(hit):
    """lrclib has the odd junk upload ("probe", one line): skip those."""
    synced = hit.get("syncedLyrics") or ""
    plain = hit.get("plainLyrics") or ""
    return synced.count("\n") >= 3 or len(plain) >= 40


def result(hit):
    synced = parse_lrc(hit.get("syncedLyrics"))
    plain = (hit.get("plainLyrics") or "").strip()
    if not synced and not plain:
        return {"none": True, "instrumental": bool(hit.get("instrumental"))}
    return {"synced": synced, "plain": plain}


def lookup(artist, title, dur, album):
    a, t = clean_artist(artist), clean_title(title)
    # YouTube titles often carry the artist: "Artist - Song"
    if " - " in t and (not a or a.lower() in t.lower()):
        left, right = t.split(" - ", 1)
        a, t = (a or left).strip(), right.strip()
    if dur > 0:
        p = {"artist_name": a, "track_name": t, "duration": round(dur)}
        if album:
            p["album_name"] = album
        hit = fetch("/get", p)
        if hit and usable(hit):
            return result(hit)
    hits = fetch("/search", {"track_name": t, "artist_name": a} if a else {"q": t}) or []
    if not hits and a:
        hits = fetch("/search", {"q": a + " " + t}) or []
    if dur > 0:      # same song within 5 s, synced first
        near = [h for h in hits if abs((h.get("duration") or 0) - dur) <= 5]
        hits = near or hits[:3]
    hits.sort(key=lambda h: (not h.get("syncedLyrics"), abs((h.get("duration") or 0) - dur)))
    for h in hits:
        if usable(h):
            return result(h)
    return {"none": True}


def main():
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    artist, title = sys.argv[1].strip(), sys.argv[2].strip()
    try:
        dur = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
    except ValueError:
        dur = 0.0
    album = sys.argv[4].strip() if len(sys.argv) > 4 else ""
    if not title:
        print(json.dumps({"none": True}))
        return
    key = hashlib.sha1(f"{artist}\x1f{title}\x1f{round(dur)}".encode()).hexdigest()
    path = os.path.join(CACHE, key + ".json")
    try:
        with open(path) as f:
            cached = json.load(f)
        if not cached.get("none") or time.time() - os.path.getmtime(path) < MISS_TTL:
            print(json.dumps(cached))
            return
    except (OSError, ValueError):
        pass
    try:
        res = lookup(artist, title, dur, album)
    except Exception as e:            # offline, timeout, bad JSON: try again next time
        print(json.dumps({"error": str(e)[:200]}))
        return
    os.makedirs(CACHE, exist_ok=True)
    with open(path + ".tmp", "w") as f:
        json.dump(res, f)
    os.replace(path + ".tmp", path)
    print(json.dumps(res))


if __name__ == "__main__":
    main()
