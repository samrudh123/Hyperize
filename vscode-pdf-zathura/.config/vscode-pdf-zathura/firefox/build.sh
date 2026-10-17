#!/bin/sh
# Pack the Firefox extension (pdf-zathura.xpi) around the viewer in ../media
# that the VS Code extension uses, and register the native host that feeds
# it zathurarc. Release Firefox only installs signed add-ons: see README.md.
set -e
cd "$(dirname "$0")"
here=$PWD
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
cp manifest.json background.js shim.js viewer.html icon.svg "$stage/"
cp -r ../media "$stage/"
find "$stage" -name '*.orig-download' -delete
rm -f pdf-zathura.xpi
(cd "$stage" && zip -qr "$here/pdf-zathura.xpi" .)
echo "built $here/pdf-zathura.xpi"

hosts="$HOME/.mozilla/native-messaging-hosts"
mkdir -p "$hosts"
cat > "$hosts/pdf_zathura.json" <<JSON
{
  "name": "pdf_zathura",
  "description": "zathurarc for the PDF in Zathura Firefox extension",
  "path": "$here/host.py",
  "type": "stdio",
  "allowed_extensions": ["pdf-zathura@samrudh.local"]
}
JSON
echo "registered native host in $hosts/pdf_zathura.json"
