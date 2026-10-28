#!/bin/sh
# Pack the extension (firefox-media-title-sync.xpi) and install it into Zen.
# Firefox — on the phone too — only installs signed add-ons: see README.md.
set -e
cd "$(dirname "$0")"
here=$PWD
rm -f firefox-media-title-sync.xpi
(cd extension && zip -qr "$here/firefox-media-title-sync.xpi" .)
echo "built $here/firefox-media-title-sync.xpi"
# Zen (the browser): installed unsigned, straight from this build — no AMO
# signing needed there (zen-install-xpi; loads when Zen next starts)
[ -x "$HOME/.local/bin/zen-install-xpi" ] && "$HOME/.local/bin/zen-install-xpi" "$here/firefox-media-title-sync.xpi" || true
