#!/bin/sh
# Build the "Video fullscreen" extension for both browsers and register the
# native host (~/.config/hypr/video-fullscreen.py) with each. See README.md
# for the one-time install (Firefox: sign on AMO; Brave: load unpacked).
set -e
cd "$(dirname "$0")"
here=$PWD
host="$HOME/.config/hypr/video-fullscreen.py"

# Firefox: an xpi (release Firefox installs only signed add-ons)
rm -f video-fullscreen.xpi
tmp=$(mktemp -d)
cp content.js background.js icon.svg "$tmp"/
cp manifest.firefox.json "$tmp"/manifest.json
(cd "$tmp" && zip -q "$here/video-fullscreen.xpi" manifest.json content.js background.js icon.svg)
rm -rf "$tmp"
echo "built $here/video-fullscreen.xpi"

# Brave / Chromium: an unpacked folder (brave://extensions -> Load unpacked).
# manifest "key" pins the ID, so the host manifest below can name it.
rm -rf chromium
mkdir chromium
cp content.js background.js icon.png chromium/
cp manifest.chromium.json chromium/manifest.json
echo "built $here/chromium/"

ff="$HOME/.mozilla/native-messaging-hosts"
mkdir -p "$ff"
cat > "$ff/video_fullscreen.json" <<JSON
{
  "name": "video_fullscreen",
  "description": "Tags a fullscreen video's window for Hyprland (video-fullscreen.py)",
  "path": "$host",
  "type": "stdio",
  "allowed_extensions": ["video-fullscreen@samrudh.local"]
}
JSON
echo "registered native host in $ff/video_fullscreen.json"

for dir in "$HOME/.config/BraveSoftware/Brave-Browser" "$HOME/.config/chromium" "$HOME/.config/google-chrome"; do
    [ -d "$dir" ] || continue
    mkdir -p "$dir/NativeMessagingHosts"
    cat > "$dir/NativeMessagingHosts/video_fullscreen.json" <<JSON
{
  "name": "video_fullscreen",
  "description": "Tags a fullscreen video's window for Hyprland (video-fullscreen.py)",
  "path": "$host",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://adadbcfmpdifbfgbkbfaiaiphnfmkpip/"]
}
JSON
    echo "registered native host in $dir/NativeMessagingHosts/video_fullscreen.json"
done
