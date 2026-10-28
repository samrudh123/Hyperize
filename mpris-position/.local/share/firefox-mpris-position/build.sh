#!/bin/sh
# Pack the extension (firefox-mpris-position.xpi), install it into Zen and
# register the native host (host.py) that publishes the tabs on MPRIS.
# Release Firefox only installs signed add-ons: see README.md.
set -e
cd "$(dirname "$0")"
here=$PWD
rm -f firefox-mpris-position.xpi
(cd extension && zip -qr "$here/firefox-mpris-position.xpi" .)
echo "built $here/firefox-mpris-position.xpi"
# Zen (the browser): installed unsigned, straight from this build — no AMO
# signing needed there (zen-install-xpi; loads when Zen next starts)
[ -x "$HOME/.local/bin/zen-install-xpi" ] && "$HOME/.local/bin/zen-install-xpi" "$here/firefox-mpris-position.xpi" || true

hosts="$HOME/.mozilla/native-messaging-hosts"
mkdir -p "$hosts"
cat > "$hosts/firefox_tabs.json" <<JSON
{
  "name": "firefox_tabs",
  "description": "One MPRIS player per Firefox tab playing YouTube (mpris-position extension)",
  "path": "$HOME/.local/share/firefox-mpris-position/host.py",
  "type": "stdio",
  "allowed_extensions": ["mpris-position@samrudh.local"]
}
JSON
echo "registered native host in $hosts/firefox_tabs.json"
