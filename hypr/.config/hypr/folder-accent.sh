#!/bin/bash
# Colour the folder icons with the desktop accent.
#
#   folder-accent.sh <hex | catppuccin name>     e.g. f9e2af, #89b4fa, mauve
#
# The icon theme is Papirus-Mocha, a small user theme in
# ~/.local/share/icons/Papirus-Mocha: Catppuccin's Papirus folders
# (github.com/catppuccin/papirus-folders, Mocha, all 14 accents, as real
# files) on top of Papirus-Dark, which it inherits for everything else.
# The generic names apps ask for — folder, folder-documents, user-home, … (one
# list per size, in places/.generics) — are symlinks; this re-points them at
# the chosen colour, the same thing upstream's papirus-folders script does to
# a system-wide Papirus, without root. Aliases (folder-home -> user-home …)
# point at the generics and never change.
#
# A hex that is not a Mocha accent (the accent picker allows any colour) gets
# the NEAREST one, as app-accent.sh does for Discord. Called by app-accent.sh
# on every accent change; running apps are nudged to reload their icons by
# flipping the icon theme away and back.

set -u

THEME="$HOME/.local/share/icons/Papirus-Mocha"
[ -d "$THEME" ] || { echo "folder-accent: $THEME missing" >&2; exit 1; }

arg="${1:-}"; arg="${arg#\#}"; arg="${arg,,}"
[ -n "$arg" ] || { echo "usage: folder-accent.sh <hex|name>" >&2; exit 2; }

name=$(python3 - "$arg" <<'EOF'
import sys
mocha = {"rosewater":"f5e0dc","flamingo":"f2cdcd","pink":"f5c2e7","mauve":"cba6f7",
         "red":"f38ba8","maroon":"eba0ac","peach":"fab387","yellow":"f9e2af",
         "green":"a6e3a1","teal":"94e2d5","sky":"89dceb","sapphire":"74c7ec",
         "blue":"89b4fa","lavender":"b4befe"}
a = sys.argv[1]
if a in mocha:
    print(a); sys.exit()
rgb = lambda h: tuple(int(h[i:i+2], 16) for i in (0, 2, 4))
t = rgb(a)
print(min(mocha, key=lambda n: sum((x-y)**2 for x, y in zip(rgb(mocha[n]), t))))
EOF
) || { echo "folder-accent: bad colour: $1" >&2; exit 2; }

current="$(cat "$THEME/.colour" 2>/dev/null)"
for dir in "$THEME"/*/places; do
    [ -L "$dir" ] && continue                  # 16x16 is a link to 22x22
    while IFS= read -r g; do
        [ -n "$g" ] || continue
        kind="${g%%-*}"; rest="${g#"$kind"}"   # folder-documents -> folder + -documents
        target="$kind-cat-mocha-$name$rest.svg"
        [ -e "$dir/$target" ] && ln -sfn "$target" "$dir/$g.svg"
    done < "$dir/.generics"
done
printf '%s\n' "$name" > "$THEME/.colour"

# Running GTK apps cache icons: flip the theme away and back so they reload.
# Only when the colour changed and Papirus-Mocha is the active theme.
if [ "$current" != "$name" ] && \
   [ "$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null)" = "'Papirus-Mocha'" ]; then
    gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'
    sleep 0.3
    gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Mocha'
fi
echo "folders: $name"
