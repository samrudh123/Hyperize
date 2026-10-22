#!/bin/bash
# Recolour the whole environment's accent — SUPER+ALT+C opens the picker,
# this script does the work.
#
#   set-accent.sh <hex>        set the accent (hex with or without a leading #)
#   set-accent.sh --preview <hex>   cheap live preview: only what reloads
#                                   instantly. Does NOT touch hyprland.conf.
#   set-accent.sh --restore    re-apply the saved accent (used at login)
#   set-accent.sh --revert     restore the pristine pre-theming configs
#   set-accent.sh --resync     re-derive templates after editing a themed file
#   set-accent.sh --show       print the current accent
#
# HOW IT WORKS — templates, not in-place edits
#
# The accent is hardcoded in twelve files in four different syntaxes:
#
#     @define-color mauve #cba6f7      waybar CSS
#     #cba6f7                          nwg-* CSS, wallpaper-grid.py
#     rgba(cba6f7ee)                   hyprland.conf, hyprlock.conf
#     cba6f7ff                         fuzzel.ini, slurp in screenshot.sh
#
# Rewriting those in place, repeatedly, is how config files rot: one bad regex
# on the tenth pass and the colour is half-changed with no way back. So on
# first run we snapshot each file twice — once verbatim into backup/ (the
# revert point) and once into templates/ with the bare hex replaced by a
# token. Every later change regenerates the real file FROM ITS TEMPLATE. The
# live files are always derived, never edited, so there is no drift and no
# accumulation of failed substitutions.
#
# The token replaces only the six hex digits, so the surrounding syntax —
# the `#`, the `rgba(...)`, the `ee`/`ff` alpha suffix — survives untouched
# and one token covers all four formats.
#
# Note hyprland.conf's border is a GRADIENT, all three stops the accent at
# falling alpha (a bevel), and the focused window's shadow is the accent too.
#
# DELIBERATELY NOT THEMED
# `bat/themes/Catppuccin Mocha.tmTheme` and its identical twin
# `yazi/Catppuccin-mocha.tmTheme` also contain the mauve hex, 19 times each,
# but there it is a SYNTAX TOKEN colour, not a UI accent — the scope list is
# `keyword, keyword.operator.word, storage.type, storage.modifier, ...`.
# Recolouring those would repaint language keywords: pick green and keywords
# become the same green as string literals, which costs real readability for
# no visual gain. Syntax highlighting is left on Catppuccin Mocha.
#
# ghostty/config has no accent to change — its palette is the ANSI 16 plus
# background/foreground, and mauve is not among them. Its cursor is rosewater
# (#f5e0dc), which is its own Catppuccin role rather than the accent, so it is
# left alone too. If you ever want the cursor to track the accent, change
# `cursor-color` to cba6f7, add `.config/ghostty/config` to the manifest, and
# run --resync.
#
# ⚠ EDITING A THEMED FILE
# Because the live files are regenerated from templates/, any edit you make to
# one of the twelve files below is LOST the next time the accent changes — the
# render overwrites it from a template that never saw your edit. This is not
# hypothetical: adding the SUPER+ALT+C keybind to hyprland.conf right after
# the first snapshot would have silently reverted it on the next colour pick.
#
# So after editing any file in the manifest:
#
#     set-accent.sh --resync
#
# which replays your edit onto the template by diffing the live file against
# the template rendered at the current accent. Idempotent, and safe to run
# whenever you are unsure — files with no edits are left untouched.

set -u

HYPR="$HOME/.config/hypr"
THEME="$HYPR/theme"
TEMPLATES="$THEME/templates"
BACKUP="$THEME/backup"
STATE="$THEME/accent"
ORIGINAL="cba6f7"          # the accent these configs shipped with
TOKEN="@@ACCENT@@"

# THEMES (SUPER+SHIFT+T, set-theme.sh). The templates stay Catppuccin Mocha; for
# any other theme each template is first passed through rice-theme.py's
# palette substitution (every Mocha colour -> the theme's colour for the same
# role) and THEN gets the accent. The substituted templates are cached per
# theme in theme/rendered/<id>/ (rebuilt when a template or rice-theme.py is
# newer), so the accent picker's live preview stays instant. At Mocha the
# templates are used as they are.
RICE="$HYPR/rice-theme.py"
THEME_ID=$(cat "$THEME/name" 2>/dev/null)
[ -n "$THEME_ID" ] || THEME_ID=mocha

tpl_for() {   # $1 = template name -> path of it in the current theme's colours
    local t="$TEMPLATES/$1"
    if [ "$THEME_ID" = mocha ]; then printf '%s\n' "$t"; return; fi
    local c="$THEME/rendered/$THEME_ID/$1"
    if [ ! -f "$c" ] || [ "$t" -nt "$c" ] || [ "$RICE" -nt "$c" ]; then
        mkdir -p "${c%/*}"
        /usr/bin/python3 "$RICE" subst "$THEME_ID" < "$t" > "$c.tmp" && mv -f "$c.tmp" "$c"
    fi
    printf '%s\n' "$c"
}

# template-relative-name : real path
# (flat names so templates/ needs no subdirectories)
manifest() {
    cat <<'EOF'
waybar-style.css	.config/waybar/style.css
waybar-dock.css	.config/waybar/dock.css
waybar-config.jsonc	.config/waybar/config.jsonc
hyprland.conf	.config/hypr/hyprland.conf
hyprlock.conf	.config/hypr/hyprlock.conf
screenshot.sh	.config/hypr/screenshot.sh
wallpaper-grid.py	.config/hypr/wallpaper-grid.py
nwg-dock-style.css	.config/nwg-dock-hyprland/style.css
nwg-dock-task-single.svg	.local/share/nwg-dock-hyprland/images/task-single-vertical.svg
nwg-dock-task-multiple.svg	.local/share/nwg-dock-hyprland/images/task-multiple-vertical.svg
nwg-bar-style.css	.config/nwg-bar/style.css
nwg-drawer.css	.config/nwg-drawer/drawer.css
gtk4.css	.config/gtk-4.0/gtk.css
obs-catppuccin-rice.ovt	.config/obs-studio/themes/Catppuccin_Mocha_Rice.ovt
mako-config	.config/mako/config
fuzzel.ini	.config/fuzzel/fuzzel.ini
yazi-theme.toml	.config/yazi/theme.toml
btop-mocha.theme	.config/btop/themes/catppuccin_mocha.theme
starship.toml	.config/starship.toml
tmux.conf	.config/tmux/tmux.conf
vscode-settings.json	.config/Code/User/settings.json
firefox-userChrome.css	.mozilla/firefox/er3XIFsH.Profile 1/chrome/userChrome.css
firefox-userContent.css	.mozilla/firefox/er3XIFsH.Profile 1/chrome/userContent.css
ghostty-config	.config/ghostty/config
zathurarc	.config/zathura/zathurarc
EOF
}

# Files cheap enough to rewrite on every preview keystroke. hyprland.conf is
# deliberately NOT here — its border is previewed with `hyprctl keyword`
# instead, so the master config is only ever written on a real commit.
PREVIEW_SET="waybar-style.css waybar-dock.css mako-config"

say() { command -v notify-send >/dev/null && notify-send -a "Accent" "$@" 2>/dev/null; }

norm() { printf '%s' "${1#\#}" | tr 'A-Z' 'a-z'; }

valid() { [[ "$(norm "$1")" =~ ^[0-9a-f]{6}$ ]]; }

# Snapshot any manifest entry that does not have a template yet.
#
# Deliberately PER FILE rather than "skip everything if templates/ exists":
# entries get added to the manifest over time (the TUI apps came later than
# the GTK ones), and a directory-level guard would silently ignore them —
# the new file would never be templated and picking a colour would appear to
# do nothing to it.
#
# A file is only ever snapshotted while it still contains the ORIGINAL accent,
# so an already-recoloured file can never be captured as "pristine".
init() {
    mkdir -p "$TEMPLATES" "$BACKUP"
    local name rel src new=0
    while IFS=$'\t' read -r name rel; do
        src="$HOME/$rel"
        [ -f "$src" ] || { echo "skip (missing): $rel" >&2; continue; }
        [ -f "$TEMPLATES/$name" ] && continue          # already managed
        cp -a "$src" "$BACKUP/$name"
        sed "s/$ORIGINAL/$TOKEN/gI" "$src" > "$TEMPLATES/$name"
        new=$((new + 1))
    done < <(manifest)
    [ -s "$STATE" ] || printf '%s\n' "$ORIGINAL" > "$STATE"
    [ "$new" -gt 0 ] && echo "snapshotted $new new file(s) into $BACKUP"
    return 0
}

# The sed program that fills a template in at accent $1: @@ACCENT@@ itself,
# plus the colours rice-theme.py derives from it (@@ACCENT_COMP@@, the
# complementary hue, and darker tints — see derive() there). ghostty-config
# maps them onto 256-colour slots 53-56, which the shell draws with
# (starship, fastfetch, eza, fzf): reloading ghostty recolours all of it live.
fill_expr() {
    local hex="$1" expr="s/$TOKEN/$1/g" k v
    while read -r k v; do
        expr+="; s/@@${k}@@/$v/g"
    done < <(/usr/bin/python3 "$RICE" derive "$hex" "$THEME_ID" 2>/dev/null)
    printf '%s\n' "$expr"
}

# Regenerate the given template names (default: all) at the given colour.
render() {
    local hex="$1"; shift
    local only=" $* "
    local name rel dst
    local fill; fill=$(fill_expr "$hex")
    while IFS=$'\t' read -r name rel; do
        [ "$#" -gt 0 ] && [[ "$only" != *" $name "* ]] && continue
        [ -f "$TEMPLATES/$name" ] || continue
        dst="$HOME/$rel"
        # A stow file-package links the file itself (starship.toml, VS Code's
        # settings.json, gtk-4.0/gtk.css): write THROUGH the link, or the mv
        # below replaces it with a plain copy and ~/Hyperize silently goes stale.
        [ -L "$dst" ] && dst=$(readlink -f "$dst")
        # Render to a temp file in the same directory and move it into place,
        # so a half-written config can never be read by anything.
        local tmp="$dst.accent-tmp.$$"
        sed "$fill" "$(tpl_for "$name")" > "$tmp" || { rm -f "$tmp"; continue; }
        # Preserve the original mode (screenshot.sh and wallpaper-grid.py are
        # executable; a plain > would have kept the temp file's 644).
        chmod --reference="$dst" "$tmp" 2>/dev/null
        mv -f "$tmp" "$dst"
    done < <(manifest)
}

# Everything that can change without restarting a process.
reload_live() {
    local hex="$1"
    # Window borders: set directly, so hyprland.conf stays untouched until
    # the choice is committed.
    # The 3D look is the bevel border AND the accent shadow (hyprland.conf,
    # general / decoration:shadow) — keep these in step with it.
    hyprctl keyword general:col.active_border \
        "rgba(${hex}ff) rgba(${hex}cc) rgba(${hex}33) 135deg" >/dev/null 2>&1
    hyprctl keyword decoration:shadow:color "rgba(${hex}77)" >/dev/null 2>&1
    # Both bars repaint by themselves: they set "reload_style_on_change", so
    # waybar re-reads style.css (bottom.css @imports it) the moment render()
    # moves the new file into place. No signal is sent on purpose — SIGUSR2
    # (full reload) ABORTS whichever of the two waybar instances does not own
    # the shared D-Bus name fr.arouillard.waybar:
    #   GLib-GIO:ERROR:gapplicationimpl-dbus.c:851:g_application_impl_command_line:
    #   assertion failed: (object_id != 0)
    # That is what made SUPER+ALT+C "toggle the top bar off" — it had crashed.
    # The one accent in config.jsonc (calendar month header) needs a real
    # restart, so commit restarts the bars properly via reload.sh bar.

    # That reload DESTROYS AND RECREATES waybar's layer surface, which used to
    # cost the dock its geometry: exclusive zones resolve in surface-creation
    # order, so the dock — suddenly the OLDER surface — claimed its zone first
    # and jumped to y=6 at full screen height, shoving waybar to x=84. This
    # function answered that with a hide/show (SIGRTMIN+3 then +2) to re-commit
    # the dock's surface and put it back on top of the ordering.
    #
    #   healthy        waybar 0 0 1920 40   dock 6 46 78 1148
    #   after SIGUSR2  waybar 84 0 1836 40  dock 6  6 78 1188
    #
    # That is gone: the dock takes no exclusive zone now, so there is no
    # ordering to lose (verified — SIGUSR2 leaves it at `6 170 78 900`). The
    # hide/show is removed rather than kept "just in case", because on the
    # --preview path it fired on every keystroke and force-SHOWED a sidebar the
    # user had toggled away.

    makoctl reload 2>/dev/null

    # zathura: every window owns a bus name and re-reads zathurarc on request.
    busctl --user list --no-legend 2>/dev/null |
        awk '$1 ~ /^org\.pwmt\.zathura\.PID-/ {print $1}' |
        while read -r name; do
            busctl --user call "$name" /org/pwmt/zathura org.pwmt.zathura SourceConfig >/dev/null 2>&1
        done

    # tmux re-reads on demand, so it can recolour without restarting. The
    # other TUI apps (yazi, btop) read their theme once at startup and have no
    # reload hook, so they pick the new accent up the next time you open them.
    # starship re-renders every prompt, so a new shell prompt is already right.
    if pgrep -x tmux >/dev/null 2>&1; then
        tmux source-file "$HOME/.config/tmux/tmux.conf" 2>/dev/null
    fi
}

# Apps that can recolour in place but only on a nudge — run on a COMMITTED
# change (pick, --restore, --revert), never on --preview: these files are not
# in PREVIEW_SET, so a preview keystroke would only make them reload the old
# colours. Everything here is a no-op when the app isn't running.
# zsh in terminals other than Ghostty draws its accent with palette slots
# 53-56 as well, but those terminals never read Ghostty's config: each such
# interactive zsh registers its tty in $XDG_RUNTIME_DIR/accent-ttys/<pid>
# (.zshrc), and this re-sends the slots there as OSC 4. The terminal repaints
# text already on screen, the same as a Ghostty reload does.
retint_ttys() {
    local reg="${XDG_RUNTIME_DIR:-/tmp}/accent-ttys" seq="" slot f pid tty seen=" "
    [ -d "$reg" ] || return 0
    while IFS= read -r slot; do                     # 53=#rrggbb
        seq+=$'\e]4;'"${slot%%=*};${slot#*=}"$'\e\\'
    done < <(sed -n 's/^palette = \(5[3-6]=#[0-9a-fA-F]\{6\}\).*/\1/p' "$HOME/.config/ghostty/config")
    [ -n "$seq" ] || return 0
    for f in "$reg"/*; do
        [ -f "$f" ] || continue
        pid=${f##*/}
        # a shell that died without its zshexit hook (SIGKILL, crash)
        if [ "$(cat "/proc/$pid/comm" 2>/dev/null)" != zsh ]; then rm -f "$f"; continue; fi
        IFS= read -r tty < "$f"
        [[ "$seen" == *" $tty "* ]] && continue      # nested shells share a tty
        seen+="$tty "
        [ -c "$tty" ] && [ -w "$tty" ] && printf '%s' "$seq" > "$tty" 2>/dev/null
    done
    return 0
}

reload_apps() {
    retint_ttys
    # ...and again a little later: VS Code resets its terminals to the stock
    # palette when it applies the settings.json just rendered, which lands
    # AFTER the send above and wipes it. (Its shells also re-send at every
    # prompt — .zshrc — but this keeps an idle terminal live.)
    ( sleep 1; retint_ttys; sleep 2; retint_ttys ) >/dev/null 2>&1 &
    # Ghostty >= 1.2 re-reads its config on SIGUSR2: open terminals pick up
    # the new cursor / selection / split divider / search colours.
    pkill -USR2 -x ghostty 2>/dev/null
    # btop re-reads btop.conf AND its theme file on SIGUSR2 (tested: a running
    # btop switched to the new colour ~2 s later).
    pkill -USR2 -x btop 2>/dev/null
    # Claude Code: regenerate ~/.claude/themes/rice.json (theme "custom:rice");
    # it watches that folder, so running sessions recolour by themselves.
    /usr/bin/python3 "$HOME/.config/hypr/claude-theme.py" 2>/dev/null
    # yazi has no reload at all: each file-manager yazi quits and its launcher
    # (~/.config/yazi/yazi-live.sh) reopens it on the same files/tabs.
    "$HOME/.config/yazi/yazi-live.sh" --relaunch-all >/dev/null 2>&1 &
    return 0
}

case "${1:-}" in
    --show)
        init >/dev/null
        cat "$STATE" 2>/dev/null || echo "$ORIGINAL"
        ;;
    --preview)
        hex="$(norm "${2:-}")"
        valid "$hex" || { echo "bad colour: ${2:-}" >&2; exit 1; }
        init >/dev/null
        render "$hex" $PREVIEW_SET
        reload_live "$hex"
        ;;
    --resync)
        # Absorb manual edits to themed files back into the templates.
        #
        # THIS IS DELIBERATELY NOT "sed the current accent back to a token".
        # That was the first implementation and it is actively destructive on
        # multi-colour theme files. yazi/theme.toml contains 40 accent
        # occurrences AND about 100 uses of Catppuccin's own green. Resync
        # while the accent happens to BE that green and the needle matches all
        # 140; the next render then paints every one of them the accent and
        # the theme is gone. Same trap for any accent that collides with a
        # colour the file already uses natively.
        #
        # So instead: render the template at the current accent, diff that
        # against the live file, and replay THAT DIFF onto the template. A
        # file with no edits produces no diff and is left alone, and an edit
        # is carried across without ever pattern-matching on a colour.
        init >/dev/null
        hex="$ORIGINAL"
        [ -s "$STATE" ] && IFS= read -r hex < "$STATE"
        valid "$hex" || hex="$ORIGINAL"
        updated=0; clean=0; failed=0
        fill=$(fill_expr "$hex")
        while IFS=$'\t' read -r name rel; do
            src="$HOME/$rel"
            tpl="$TEMPLATES/$name"
            [ -f "$src" ] && [ -f "$tpl" ] || continue
            rendered="$(mktemp)"
            # rendered in the current theme; the diff is replayed onto the
            # Mocha template (an edit to a COLOUR line made under another
            # theme carries that theme's hex — edit the template by hand then)
            sed "$fill" "$(tpl_for "$name")" > "$rendered"
            if cmp -s "$rendered" "$src"; then
                clean=$((clean + 1))
                rm -f "$rendered"
                continue
            fi
            pf="$(mktemp)"
            diff -u "$rendered" "$src" > "$pf"      # exit 1 just means "differs"
            if patch -s -f "$tpl" < "$pf" 2>/dev/null; then
                updated=$((updated + 1))
            else
                # Only happens if the edit sits within patch context of an
                # accent line, where the template holds a token and the diff
                # holds the literal hex. Refuse rather than guess.
                failed=$((failed + 1))
                echo "resync: could not replay edits to $rel" >&2
                echo "  edit theme/templates/$name by hand (accent = $TOKEN)" >&2
            fi
            rm -f "$rendered" "$pf"
        done < <(manifest)
        echo "resync: $updated updated, $clean already current, $failed failed"
        [ "$failed" -gt 0 ] && exit 1
        exit 0
        ;;
    --restore)
        init >/dev/null
        hex="$ORIGINAL"
        [ -s "$STATE" ] && IFS= read -r hex < "$STATE"
        valid "$hex" || hex="$ORIGINAL"
        render "$hex"
        reload_live "$hex"
        reload_apps
        # No-op unless the apps are behind the saved accent (see app-accent.sh).
        hyprctl dispatch exec "$HYPR/app-accent.sh $hex" >/dev/null
        ;;
    --revert)
        # Put the pristine files back, exactly as they were before any theming.
        [ -d "$BACKUP" ] || { echo "nothing to revert to" >&2; exit 1; }
        while IFS=$'\t' read -r name rel; do
            [ -f "$BACKUP/$name" ] && cp -a "$BACKUP/$name" "$HOME/$rel"
        done < <(manifest)
        printf '%s\n' "$ORIGINAL" > "$STATE"
        reload_live "$ORIGINAL"
        reload_apps
        say "Reverted to the original theme"
        ;;
    "")
        echo "usage: set-accent.sh <hex> | --preview <hex> | --restore | --revert | --resync | --show" >&2
        exit 2
        ;;
    *)
        hex="$(norm "$1")"
        valid "$hex" || { echo "bad colour: $1" >&2; exit 1; }
        init >/dev/null
        render "$hex"
        printf '%s\n' "$hex" > "$STATE"
        reload_live "$hex"
        reload_apps
        # No bar restart: the bars and dock are Quickshell since 2026-10-09
        # and follow theme/accent (written above) live. Restarting the shell
        # here also cut short the wallpaper transition the picker had just
        # started. (The waybar-era restart is in set-accent.sh.pre-quickshell (archived in ~/.dotfiles-backup/pre-backups-2026-10-17.tar.gz).)
        # Spotify / YouTube Music / Discord — slow (spicetify refresh, app
        # restarts), so detached through Hyprland rather than waited on.
        hyprctl dispatch exec "$HYPR/app-accent.sh $hex" >/dev/null
        [ -n "${RICE_QUIET:-}" ] || say "Accent set to #$hex"   # set-theme.sh says its own
        ;;
esac
