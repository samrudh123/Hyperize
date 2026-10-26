#!/bin/bash
# Switch the whole desktop's colour theme — SUPER+SHIFT+T opens the picker
# (~/.config/quickshell/ThemePicker.qml), which calls this.
#
#   set-theme.sh <id>          mocha tokyonight gruvbox nord rosepine
#                              everforest dracula kanagawa
#   set-theme.sh --restore     re-apply the saved theme (login)
#   set-theme.sh --show        print the current theme id
#
# Palettes live in rice-theme.py. A theme is applied by re-rendering the
# accent machinery in the new colours:
#   * the accent keeps its ROLE (blue stays the theme's blue, …; a custom hex
#     moves to the theme's nearest accent) — rice-theme.py map-accent
#   * theme/name + theme/palette.json — the Quickshell shell re-reads the
#     palette live (Theme.qml), no restart
#   * set-accent.sh renders every template through the palette (Hyprland,
#     hyprlock, mako, fuzzel, GTK4/libadwaita CSS, yazi, btop, tmux, starship,
#     VS Code, Zen (live, via its autoconfig), OBS, Ghostty, the waybar fallback …) and runs
#     app-accent.sh, which follows the theme too (GTK3 theme, KDE/Qt colours,
#     Spotify, YouTube Music, Discord, LibreOffice)
#   * then the things that only re-read on a nudge: Hyprland (reload — the
#     inactive border / shadow are in the rendered config), Ghostty (SIGUSR2
#     reloads its config), bat's theme cache, yazi's preview theme.
# Apps that read colours only at start (VS Code's window chrome until
# it re-reads settings, KDE apps, LibreOffice) change on their next start.

set -u

HYPR="$HOME/.config/hypr"
THEME="$HYPR/theme"
RICE="$HYPR/rice-theme.py"
PY=/usr/bin/python3

say() { command -v notify-send >/dev/null && notify-send -a "Theme" "$@" 2>/dev/null; }

current=$($PY "$RICE" current)

case "${1:-}" in
    --show) echo "$current"; exit 0 ;;
    --restore) id="$current" ;;
    "") echo "usage: set-theme.sh <id> | --restore | --show" >&2; exit 2 ;;
    *) id="$1" ;;
esac

$PY "$RICE" palette "$id" > "$THEME/palette.json.tmp" 2>/dev/null \
    || { rm -f "$THEME/palette.json.tmp"; echo "unknown theme: $id" >&2; exit 2; }

accent=$(cat "$THEME/accent" 2>/dev/null)
[[ "$accent" =~ ^[0-9a-fA-F]{6}$ ]] || accent=cba6f7
newaccent=$($PY "$RICE" map-accent "$accent" "$current" "$id")

# Dock icons in the new colours BEFORE the shell sees the new palette (the
# dock reloads its icons when the theme id changes).
RICE_PALETTE="$THEME/palette.json.tmp" $PY "$HYPR/dock-theme-icons.py" >/dev/null 2>&1

printf '%s\n' "$id" > "$THEME/name"
mv -f "$THEME/palette.json.tmp" "$THEME/palette.json"

# Re-render everything at the (carried-over) accent in the new palette.
# app-accent.sh (run by set-accent.sh) skips when theme + accent are what it
# last applied; a theme switch / restore always wants it, so clear that.
printf 'force\n' > "$THEME/app-accent"
RICE_QUIET=1 "$HYPR/set-accent.sh" "$newaccent" >/dev/null

# Syntax themes used for previews: pristine Mocha copies, recoloured.
pristine="$THEME/pristine"
mkdir -p "$pristine"
for f in "$HOME/.config/bat/themes/Catppuccin Mocha.tmTheme" \
         "$HOME/.config/yazi/Catppuccin-mocha.tmTheme"; do
    [ -f "$f" ] || continue
    keep="$pristine/$(basename "$(dirname "$f")")-$(basename "$f")"
    [ -f "$keep" ] || cp -a "$f" "$keep"
    $PY "$RICE" subst "$id" < "$keep" > "$f.tmp" && mv -f "$f.tmp" "$f"
done
command -v bat >/dev/null && bat cache --build >/dev/null 2>&1

hyprctl reload >/dev/null
pkill -USR2 -x ghostty 2>/dev/null     # Ghostty >= 1.2 reloads its config
command -v makoctl >/dev/null && makoctl reload 2>/dev/null

[ "${1:-}" = --restore ] || say "Theme: $($PY -c "import json;print(json.load(open('$THEME/palette.json'))['name'])")"
exit 0
