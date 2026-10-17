#!/bin/sh
# Pack the Firefox extension (dl-popup.xpi) and register the native host
# (native-host.py) it talks to. Release Firefox only installs signed add-ons:
# see README.md.
set -e
cd "$(dirname "$0")"
here=$PWD
rm -f dl-popup.xpi
(cd firefox-extension && zip -qr "$here/dl-popup.xpi" .)
echo "built $here/dl-popup.xpi"

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
