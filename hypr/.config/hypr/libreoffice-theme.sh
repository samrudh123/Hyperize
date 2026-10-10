#!/bin/bash
# LibreOffice in Catppuccin Mocha with the desktop accent.
#
#   libreoffice-theme.sh [hex]     hex defaults to the saved accent (theme/accent)
#
# The window chrome (menus, toolbars, dialogs) needs nothing here: LibreOffice
# draws through its gtk3 plugin, so it already wears the Catppuccin GTK theme
# app-accent.sh selects. This sets the rest, in registrymodifications.xcu:
#
#   * Tools > Options > Appearance > Application colours: Catppuccin's own
#     LibreOffice schemes (github.com/catppuccin/libreoffice, Mocha, all 14
#     accents, kept in theme/libreoffice/) are added once, and the one for the
#     nearest Mocha accent is made current — the document canvas becomes base,
#     the area around it crust, grids/boundaries surface colours.
#   * Appearance mode Dark, and the Colibre Dark icons (Yaru's are light).
#   * The Catppuccin colour palettes (.soc) for Format > Colours.
#
# LibreOffice rewrites registrymodifications.xcu when it quits, so an edit made
# while it runs would be lost: then this waits in the background for it to
# close and applies the change after. Called by app-accent.sh.

set -u

hex="${1:-$(cat "$HOME/.config/hypr/theme/accent" 2>/dev/null)}"
hex="${hex#\#}"; hex="${hex,,}"
[[ "$hex" =~ ^[0-9a-f]{6}$ ]] || { echo "usage: libreoffice-theme.sh [hex]" >&2; exit 2; }

SRC="$HOME/.config/hypr/theme/libreoffice"
USERDIR="$HOME/.config/libreoffice/4/user"
REG="$USERDIR/registrymodifications.xcu"
[ -f "$REG" ] || { echo "libreoffice-theme: no $REG (never started?)" >&2; exit 0; }

if pgrep -x soffice.bin >/dev/null 2>&1; then
    # one waiter at a time; it re-reads the accent when it fires
    exec 9>"${XDG_RUNTIME_DIR:-/tmp}/libreoffice-theme.lock"
    flock -n 9 || exit 0
    ( while pgrep -x soffice.bin >/dev/null 2>&1; do sleep 10; done
      exec 9>&-
      "$0" ) >/dev/null 2>&1 &
    disown
    echo "libreoffice-theme: LibreOffice is open; applying when it closes"
    exit 0
fi

mkdir -p "$USERDIR/config"
cp -f "$SRC"/*.soc "$USERDIR/config/" 2>/dev/null

# THEMES: the scheme is the Catppuccin Mocha one for the accent's ROLE in the
# current theme; for another theme it is recoloured (rice-theme.py, colours
# here are decimal longs) and renamed "Rice <theme> - <role>", built once
# into theme/libreoffice-<theme>/.
RICE="$HOME/.config/hypr/rice-theme.py"
THEME_ID=$(/usr/bin/python3 "$RICE" current)
NAME=$(/usr/bin/python3 "$RICE" nearest "$hex" "$THEME_ID")
PREFIX="Catppuccin mocha"
if [ "$THEME_ID" != mocha ]; then
    PREFIX="Rice $THEME_ID"
    TSRC="$HOME/.config/hypr/theme/libreoffice-$THEME_ID"
    mkdir -p "$TSRC"
    for f in "$SRC"/catppuccin-mocha-*.xcu; do
        out="$TSRC/$(basename "$f")"
        if [ ! -f "$out" ] || [ "$f" -nt "$out" ] || [ "$RICE" -nt "$out" ]; then
            /usr/bin/python3 "$RICE" subst "$THEME_ID" --ints < "$f" 2>/dev/null \
                | sed "s/Catppuccin mocha - /$PREFIX - /g" > "$out"
        fi
    done
    SRC="$TSRC"
fi

python3 - "$REG" "$SRC" "$hex" "$NAME" "$PREFIX" <<'EOF'
import glob, os, re, shutil, sys
reg, src, hexc, name, prefix = sys.argv[1:6]

s = open(reg, encoding="utf-8").read()
end = s.rindex("</oor:items>")
add = []
for f in sorted(glob.glob(os.path.join(src, "catppuccin-mocha-*.xcu"))):
    item = open(f, encoding="utf-8").read().strip()
    scheme = re.search(r'<node oor:name="([^"]+)" oor:op="replace">', item).group(1)
    if f'oor:name="{scheme}"' not in s:
        add.append(item)

def setprop(s, path, prop, typ_value):
    line = (f'<item oor:path="{path}"><prop oor:name="{prop}" oor:op="fuse">'
            f'<value>{typ_value}</value></prop></item>')
    pat = re.compile(r'<item oor:path="%s"><prop oor:name="%s" oor:op="fuse">.*?</item>'
                     % (re.escape(path), re.escape(prop)))
    if pat.search(s):
        return pat.sub(lambda _m: line, s, count=1)
    i = s.rindex("</oor:items>")
    return s[:i] + line + "\n" + s[i:]

if add:
    s = s[:end] + "\n".join(add) + "\n" + s[end:]
s = setprop(s, "/org.openoffice.Office.UI/ColorScheme", "CurrentColorScheme",
            f"{prefix} - {name}")
s = setprop(s, "/org.openoffice.Office.Common/Appearance", "ApplicationAppearance", "2")
s = setprop(s, "/org.openoffice.Office.Common/Misc", "SymbolStyle", "colibre_dark")

if not os.path.exists(reg + ".pre-catppuccin"):
    shutil.copy2(reg, reg + ".pre-catppuccin")
tmp = reg + ".tmp"
open(tmp, "w", encoding="utf-8").write(s)
os.replace(tmp, reg)
print(f"libreoffice: {prefix} - {name}")
EOF
