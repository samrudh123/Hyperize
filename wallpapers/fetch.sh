#!/usr/bin/env bash
# Rebuild ~/Pictures/wallpapers on a new machine.
#
#   fetch.sh      download everything in sources.tsv
#
# The wallpapers themselves are not in the repo: it is public, they are other
# people's art, and the live ones alone are ~600 MB. Already-present files are
# skipped, so it is safe to re-run.
#
# post-processing column: fit3840 = downscale to 3840 px wide (JPEG q92), as on
# the source machine; h1440 = re-encode the video to 2560x1440.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="${WALLPAPER_DIR:-$HOME/Pictures/wallpapers}"

mkdir -p "$DEST"
ok=0 skip=0 fail=0
while IFS=$'\t' read -r file url post _colour _page; do
    [[ -z "$file" || "$file" == \#* ]] && continue
    if [ -e "$DEST/$file" ]; then skip=$((skip + 1)); continue; fi
    tmp="$(mktemp -p "$DEST" ".fetch.XXXXXX")"
    if ! curl -fsSL --retry 2 -A "Mozilla/5.0" -o "$tmp" "$url"; then
        echo "FAILED  $file  ($url)" >&2; rm -f "$tmp"; fail=$((fail + 1)); continue
    fi
    case "$post" in
        fit3840)
            python3 -I - "$tmp" "$DEST/$file" <<'PY' || { echo "FAILED  $file (resize)" >&2; fail=$((fail + 1)); }
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
if im.width > 3840:
    im = im.resize((3840, round(im.height * 3840 / im.width)), Image.LANCZOS)
im.save(sys.argv[2], quality=92, optimize=True)
PY
            rm -f "$tmp" ;;
        h1440)
            ffmpeg -v error -y -i "$tmp" -vf scale=2560:1440 -c:v libx264 -crf 20 -preset slow -an "$DEST/$file" \
                || { echo "FAILED  $file (re-encode)" >&2; fail=$((fail + 1)); }
            rm -f "$tmp" ;;
        noaudio)
            ffmpeg -v error -y -i "$tmp" -c copy -an "$DEST/$file" \
                || { echo "FAILED  $file (strip audio)" >&2; fail=$((fail + 1)); }
            rm -f "$tmp" ;;
        *)  mv "$tmp" "$DEST/$file" ;;
    esac
    [ -e "$DEST/$file" ] && { chmod 644 "$DEST/$file"; ok=$((ok + 1)); echo "ok      $file"; }
done < "$HERE/sources.tsv"

echo "downloaded $ok, already there $skip, failed $fail"
