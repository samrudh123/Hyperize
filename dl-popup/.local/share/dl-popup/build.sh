#!/bin/sh
# Pack the browser extension (dl-popup.xpi), install it into Zen and register
# the native host (native-host.py) it talks to. Release Firefox only installs
# signed add-ons: see README.md.
set -e
cd "$(dirname "$0")"
here=$PWD
rm -f dl-popup.xpi
(cd firefox-extension && zip -qr "$here/dl-popup.xpi" .)
echo "built $here/dl-popup.xpi"
# Zen (the browser): installed unsigned, straight from this build — no AMO
# signing needed there (zen-install-xpi; loads when Zen next starts)
[ -x "$HOME/.local/bin/zen-install-xpi" ] && "$HOME/.local/bin/zen-install-xpi" "$here/dl-popup.xpi" || true

hosts="$HOME/.mozilla/native-messaging-hosts"
mkdir -p "$hosts"
cat > "$hosts/dl_popup.json" <<JSON
{
  "name": "dl_popup",
  "description": "dl-popup: fuzzel download popup for aria2 / JDownloader",
  "path": "$here/native-host.py",
  "type": "stdio",
  "allowed_extensions": ["dl-popup@samrudh.local"]
}
JSON
echo "registered native host in $hosts/dl_popup.json"
