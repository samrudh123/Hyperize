#!/bin/bash
# Switch the whole desktop's colour theme — SUPER+SHIFT+T opens the picker
# (~/.config/quickshell/ThemePicker.qml), which calls this.
#
#   set-theme.sh <id>          mocha tokyonight gruvbox nord rosepine
#                              everforest dracula kanagawa winter
#                              (winter = a SEASONAL theme: palette + the
#                              shell's snow effects + its wallpaper)
#   set-theme.sh <id>-light    the same themes' light flavours (mocha-light =
#                              Catppuccin Latte, rosepine-light = Rosé Pine Dawn …)
#   set-theme.sh --mode dark|light   the current theme in that mode
#                              (Settings › Appearance › Mode; dark is the default)
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
    --mode)
        case "${2:-}" in dark|light) ;; *) echo "usage: set-theme.sh --mode dark|light" >&2; exit 2 ;; esac
        id=$($PY "$RICE" variant "$2" "$current")
        [ "$id" = "$current" ] && exit 0 ;;
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

# Seasonal themes (winter …) — read before the palette is replaced
pal_key() { $PY -c "import json,sys
try: print(json.load(open(sys.argv[1])).get(sys.argv[2], ''))
except Exception: print('')" "$1" "$2"; }
old_season=$(pal_key "$THEME/palette.json" season)
old_wall=$(pal_key "$THEME/palette.json" wallpaper)
new_season=$(pal_key "$THEME/palette.json.tmp" season)
new_wall=$(pal_key "$THEME/palette.json.tmp" wallpaper)

printf '%s\n' "$id" > "$THEME/name"
mv -f "$THEME/palette.json.tmp" "$THEME/palette.json"
# the theme a season replaced (Settings › Appearance › Season "Back to …")
[ -n "$new_season" ] && [ -z "$old_season" ] && printf '%s\n' "$current" > "$THEME/season-prev-theme"

# Dark / light: the switches that are flags, not colours (everything with
# colours follows the palette). Light themes are `<id>-light` (rice-theme.py).
#   * GNOME colour-scheme — libadwaita apps, and through the portal every
#     Electron / Chromium app's prefers-color-scheme
#   * GTK3's prefer-dark (Hyprland runs no XSettings daemon; settings.ini)
#   * Papirus-Mocha's base icons: Papirus-Dark's pale symbolic icons vanish on
#     light paper, so it inherits Papirus-Light there (folders stay Catppuccin)
#   * Zoom's own Appearance key in zoomus.conf (zoom.sh; next Zoom start —
#     it reads the key only when it starts)
# Claude Code, Neovim and LibreOffice read "mode" from palette.json /
# rice-theme.py themselves.
apply_mode() {
    local mode scheme pd inh icons="$HOME/.local/share/icons/Papirus-Mocha/index.theme"
    mode=$($PY "$RICE" mode "$1")
    if [ "$mode" = light ]; then scheme=prefer-light; pd=0; inh="Papirus-Light,breeze,hicolor"
    else scheme=prefer-dark; pd=1; inh="Papirus-Dark,breeze-dark,hicolor"; fi
    gsettings set org.gnome.desktop.interface color-scheme "$scheme" 2>/dev/null
    [ -f "$HOME/.config/gtk-3.0/settings.ini" ] && sed -i --follow-symlinks \
        "s/^gtk-application-prefer-dark-theme=.*/gtk-application-prefer-dark-theme=$pd/" \
        "$HOME/.config/gtk-3.0/settings.ini"
    if [ -f "$icons" ] && ! grep -qx "Inherits=$inh" "$icons"; then
        sed -i "s/^Inherits=.*/Inherits=$inh/" "$icons"
        # running GTK apps cache icons: flip the theme away and back
        if [ "$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null)" = "'Papirus-Mocha'" ]; then
            gsettings set org.gnome.desktop.interface icon-theme "${inh%%,*}"
            sleep 0.3
            gsettings set org.gnome.desktop.interface icon-theme Papirus-Mocha
        fi
    fi
    "$HOME/.config/hypr/zoom.sh" --mode-only "$mode"
}
apply_mode "$id"

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
# theme/name, palette.json, … changed length: keep `git status` clean
"$HYPR/set-accent.sh" --git-refresh >/dev/null 2>&1 &

# A seasonal theme may bring its wallpaper (rice-theme.py `wallpaper`); the one
# that was up before is kept in theme/season-prev-wallpaper and comes back
# when a normal theme is picked. A wallpaper you chose yourself while the
# season was on is left alone. Off: Settings › Appearance › Season ›
# Seasonal wallpaper (theme/season-fx.json "wallpaper": false).
season_wallpaper() {
    local prevf="$THEME/season-prev-wallpaper" cur want=""
    cur=$(cat "$HYPR/wallpaper" 2>/dev/null)
    if [ -n "$new_season" ] && [ -n "$new_wall" ]; then
        [ "$($PY -c "import json
try: print(json.load(open('$THEME/season-fx.json')).get('wallpaper', True))
except Exception: print(True)")" = True ] || return 0
        [ -f "$new_wall" ] || return 0
        if [ -z "$old_season" ] || [ -z "$old_wall" ]; then
            [ -n "$cur" ] && [ "$cur" != "$new_wall" ] && printf '%s\n' "$cur" > "$prevf"
            want="$new_wall"
        elif [ "$cur" = "$old_wall" ]; then
            want="$new_wall"                # winter night -> winter day
        fi
    elif [ -n "$old_season" ] && [ -f "$prevf" ]; then
        # also season -> a season without a wallpaper (Winter Day -> Night)
        [ -n "$old_wall" ] && [ "$cur" = "$old_wall" ] && want=$(cat "$prevf")
        rm -f "$prevf"
    fi
    [ -n "$want" ] && [ "$want" != "$cur" ] && [ -f "$want" ] \
        && setsid -f "$HYPR/set-wallpaper.sh" "$want" >/dev/null 2>&1
    return 0
}
[ "${1:-}" = --restore ] || season_wallpaper

hyprctl reload >/dev/null
pkill -USR2 -x ghostty 2>/dev/null     # Ghostty >= 1.2 reloads its config
command -v makoctl >/dev/null && makoctl reload 2>/dev/null

[ "${1:-}" = --restore ] || say "Theme: $($PY -c "import json;print(json.load(open('$THEME/palette.json'))['name'])")"
exit 0
