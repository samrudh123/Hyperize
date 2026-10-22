#!/bin/sh
# Pack the Rice Accent Firefox extension (rice-accent.xpi) and register its
# native host. Release Firefox only installs signed add-ons: see README.md.
set -e
cd "$(dirname "$0")"
here=$PWD
rm -f rice-accent.xpi
zip -q rice-accent.xpi manifest.json background.js icon.svg
echo "built $here/rice-accent.xpi"

hosts="$HOME/.mozilla/native-messaging-hosts"
mkdir -p "$hosts"
cat > "$hosts/rice_accent.json" <<JSON
{
  "name": "rice_accent",
  "description": "Desktop theme + accent for the Rice Accent Firefox extension",
  "path": "$here/host.py",
  "type": "stdio",
  "allowed_extensions": ["rice-accent@samrudh.local"]
}
JSON
echo "registered native host in $hosts/rice_accent.json"
