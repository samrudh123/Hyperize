#!/usr/bin/env bash
# Zen Browser (Firefox-based) — the official Linux tarball into
# ~/.local/opt/zen, its launcher, icon and desktop entry. Re-run to update
# (Zen's own updater can't write outside a system install either way).
#   ZEN_TAG=1.23.4b ./build/zen.sh     pin a release (default: latest)
source "$(dirname "$0")/common.sh"

ASSET=zen.linux-x86_64.tar.xz
REPO=https://github.com/zen-browser/desktop
if [ -n "${ZEN_TAG:-}" ]; then
    tag=$ZEN_TAG
else    # the latest release's tag, from the download redirect (no API rate limit)
    tag=$(curl -fsI "$REPO/releases/latest/download/$ASSET" | sed -n 's#^location: .*/download/\([^/]*\)/.*#\1#ip' | tr -d '\r')
fi
[ -n "$tag" ] || { echo "zen: could not find the latest release" >&2; exit 1; }

dl=$(mktemp -d)
trap 'rm -rf "$dl"' EXIT
curl -fsL -o "$dl/$ASSET" "$REPO/releases/download/$tag/$ASSET"
# GitHub publishes each asset's sha256 on the release page
want=$(curl -fsL "$REPO/releases/expanded_assets/$tag" | python3 -c '
import re, sys
for li in re.split(r"<li ", sys.stdin.read()):
    if re.search(r"/download/[^/]+/'"$ASSET"'\"", li):
        m = re.search(r"sha256:([0-9a-f]{64})", li)
        print(m.group(1) if m else "")
        break')
got=$(sha256sum "$dl/$ASSET" | cut -d' ' -f1)
if [ -z "$want" ] || [ "$want" != "$got" ]; then
    echo "zen: checksum mismatch for $tag ($got, expected ${want:-nothing})" >&2
    exit 1
fi

mkdir -p "$PREFIX/opt"
rm -rf "$PREFIX/opt/zen.new"
mkdir "$PREFIX/opt/zen.new"
tar -xJf "$dl/$ASSET" -C "$PREFIX/opt/zen.new" --strip-components=1
rm -rf "$PREFIX/opt/zen"
mv "$PREFIX/opt/zen.new" "$PREFIX/opt/zen"
ln -sfn "$PREFIX/opt/zen/zen" "$PREFIX/bin/zen"

# Live desktop theme + accent: an autoconfig script Zen runs at startup
# (zen/.config/zen-rice — see its README). It lives in the install dir, so
# every reinstall/update has to put it back.
RICE="$DOTFILES/zen/.config/zen-rice"
[ -d "$RICE" ] || RICE="$HOME/.config/zen-rice"
if [ -f "$RICE/rice-live.cfg" ]; then
    install -Dm644 "$RICE/autoconfig.js" "$PREFIX/opt/zen/defaults/pref/autoconfig.js"
    install -m644 "$RICE/rice-live.cfg" "$PREFIX/opt/zen/rice-live.cfg"
fi

for s in 16 32 48 64 128; do
    install -Dm644 "$PREFIX/opt/zen/browser/chrome/icons/default/default$s.png" \
        "$PREFIX/share/icons/hicolor/${s}x${s}/apps/zen.png"
done

# Absolute path: launchers run desktop entries without ~/.local/bin on PATH.
# StartupWMClass = Zen's Wayland app id (RemotingName in application.ini).
cat > "$PREFIX/share/applications/zen.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Zen Browser
GenericName=Web Browser
Comment=Firefox-based browser
Exec=$PREFIX/opt/zen/zen %u
Icon=zen
Terminal=false
StartupNotify=true
StartupWMClass=zen
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;application/x-xpinstall;application/pdf;
Actions=new-window;new-private-window;

[Desktop Action new-window]
Name=New Window
Exec=$PREFIX/opt/zen/zen --new-window %u

[Desktop Action new-private-window]
Name=New Private Window
Exec=$PREFIX/opt/zen/zen --private-window %u
EOF
update-desktop-database "$PREFIX/share/applications" 2>/dev/null || true
gtk-update-icon-cache -q "$PREFIX/share/icons/hicolor" 2>/dev/null || true
echo "zen $tag installed in $PREFIX/opt/zen"
