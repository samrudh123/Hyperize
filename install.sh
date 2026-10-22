#!/usr/bin/env bash
# Set this desktop up on an Ubuntu machine from the Hyperize repo (my dotfiles).
#
#   ./install.sh                 everything below, in order
#   ./install.sh packages        apt install packages/apt.txt          (sudo)
#   ./install.sh build           fonts, yazi, Quickshell, mpvpaper, file-picker
#                                portal, nwg-drawer into ~/.local      (~20 min)
#   ./install.sh copy            copy the configs into ~, seed the per-machine
#                                files (aria2, OBS, spicetify…)
#   ./install.sh system          systemd user units, zsh as login shell
#   ./install.sh wallpapers      download the wallpapers (wallpapers/fetch.sh)
#
# The configs are COPIED, not linked: your ~/.config is yours, and pulling a
# newer version of the repo changes nothing until you run `copy` again.
# Anything in ~ that a copy would overwrite (and that differs) is moved to
# ~/.dotfiles-backup/<date>/ first. Safe to re-run.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
BACKUP="$HOME/.dotfiles-backup/$(date +%Y-%m-%d_%H-%M-%S)"

# the config packages: each mirrors $HOME (hypr/.config/hypr/… -> ~/.config/hypr/…)
PACKAGES=(hypr quickshell yazi ghostty mako fuzzel nwg waybar portals bat btop glow fastfetch tmux
          zsh bash git dl-popup aria2 systemd environment applications bin gtk vscode zathura
          vscode-pdf-zathura nvim firefox-accent)

say() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }

# ── packages ────────────────────────────────────────────────────────────────
do_packages() {
    say "apt packages (packages/apt.txt)"
    mapfile -t pkgs < <(grep -v '^\s*#' "$REPO/packages/apt.txt" | tr ' ' '\n' | sed '/^$/d')
    sudo apt update
    sudo apt install -y "${pkgs[@]}"
}

# ── builds ──────────────────────────────────────────────────────────────────
do_build() {
    for b in fonts yazi quickshell mpvpaper termfilechooser nwg; do
        say "build: $b"
        bash "$REPO/build/$b.sh"
    done
}

# ── copy ────────────────────────────────────────────────────────────────────
COPIED=0 KEPT=0 SAVED=0
# a package's files: what git tracks (no stray backups / caches), else all
pkg_files() {
    if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
        (cd "$REPO/$1" && git ls-files -z)
    else
        (cd "$REPO/$1" && find . \( -type f -o -type l \) -print0)
    fi
}
copy_pkg() {
    local pkg=$1 rel src dst
    while IFS= read -r -d '' rel; do
        rel=${rel#./}
        src="$REPO/$pkg/$rel"
        dst="$HOME/$rel"
        # already the very same file (e.g. on the machine the repo came from)
        [ "$(readlink -f "$dst" 2>/dev/null)" = "$(readlink -f "$src")" ] && { KEPT=$((KEPT + 1)); continue; }
        if [ -e "$dst" ] || [ -L "$dst" ]; then
            if [ ! -L "$dst" ] && cmp -s "$src" "$dst"; then KEPT=$((KEPT + 1)); continue; fi
            mkdir -p "$BACKUP/$(dirname "$rel")"
            mv "$dst" "$BACKUP/$rel"
            SAVED=$((SAVED + 1))
        fi
        mkdir -p "$(dirname "$dst")"
        cp -P --preserve=mode,timestamps "$src" "$dst"
        COPIED=$((COPIED + 1))
    done < <(pkg_files "$pkg")
}

seed() {    # seed SRC DEST: copy a template once, filling in @HOME@
    local src=$1 dest=$2
    [ -e "$dest" ] && return 0
    mkdir -p "$(dirname "$dest")"
    sed "s#@HOME@#$HOME#g" "$src" > "$dest"
    echo "  seeded ${dest/#$HOME/\~}"
}

do_copy() {
    say "copying configs into ~"
    for p in "${PACKAGES[@]}"; do copy_pkg "$p"; done
    echo "  $COPIED copied, $KEPT already up to date"
    [ "$SAVED" -gt 0 ] && echo "  $SAVED changed files you had were moved to ${BACKUP/#$HOME/\~}"

    say "per-machine files (copied once, never overwritten)"
    # aria2: its RPC secret is generated here, never stored in the repo
    if [ ! -e "$HOME/.config/aria2/aria2.conf" ]; then
        secret="$(python3 -c 'import secrets; print(secrets.token_urlsafe(24))')"
        mkdir -p "$HOME/.config/aria2" "$HOME/.local/state/aria2"
        touch "$HOME/.local/state/aria2/session"
        sed -e "s#@HOME@#$HOME#g" -e "s#@SECRET@#$secret#" "$REPO/extras/aria2/aria2.conf" \
            > "$HOME/.config/aria2/aria2.conf"
        echo "  seeded ~/.config/aria2/aria2.conf (new RPC secret)"
    fi
    seed "$REPO/extras/dl-popup/config.json" "$HOME/.config/dl-popup/config.json"
    # OBS: profile, scene collection, Catppuccin theme — only on a fresh OBS
    if [ ! -d "$HOME/.config/obs-studio/basic" ]; then
        (cd "$REPO/extras/obs" && find . -type f) | while read -r f; do
            seed "$REPO/extras/obs/$f" "$HOME/.config/obs-studio/${f#./}"
        done
    fi
    if [ ! -e "$HOME/.config/spicetify/config-xpui.ini" ]; then
        mkdir -p "$HOME/.config/spicetify"
        cp -r --update=none "$REPO/extras/spicetify/." "$HOME/.config/spicetify/"
        sed -i "s#@HOME@#$HOME#g" "$HOME/.config/spicetify/config-xpui.ini"
        echo "  seeded ~/.config/spicetify"
    fi
    if [ ! -e "$HOME/.gitconfig.local" ]; then
        warn "no ~/.gitconfig.local — create it with your git name/email:"
        echo '    git config --file ~/.gitconfig.local user.name  "Your Name"'
        echo '    git config --file ~/.gitconfig.local user.email "you@example.com"'
    fi
    mkdir -p "$HOME/Videos/Recordings" "$HOME/Pictures/wallpapers"

    # VS Code's zathura-style PDF viewer: packed and installed from its source
    # (settings.json already points *.pdf at it)
    if command -v code >/dev/null && ! code --list-extensions 2>/dev/null | grep -qx local.pdf-zathura; then
        say "VS Code extension: PDF in Zathura"
        sh "$HOME/.config/vscode-pdf-zathura/build.sh" || warn "pdf-zathura extension did not install"
    fi
    # ...and its Firefox twin: the xpi still has to be signed on AMO (see its
    # README); this builds it and registers the native host that themes it
    if [ ! -e "$HOME/.mozilla/native-messaging-hosts/pdf_zathura.json" ]; then
        say "Firefox extension: PDF in Zathura"
        sh "$HOME/.config/vscode-pdf-zathura/firefox/build.sh" || warn "pdf-zathura Firefox build failed"
    fi
    # Rice Accent (Firefox follows the accent live): same deal — sign the xpi
    # on AMO (~/.config/firefox-accent/README.md); this builds it and
    # registers the native host that feeds it the theme
    if [ ! -e "$HOME/.mozilla/native-messaging-hosts/rice_accent.json" ]; then
        say "Firefox extension: Rice Accent"
        sh "$HOME/.config/firefox-accent/build.sh" || warn "rice-accent Firefox build failed"
    fi
    # dl-popup's Firefox extension: same deal (sign the xpi on AMO, see
    # ~/.local/share/dl-popup/README.md); this builds it and registers the
    # native host that hands its downloads to the popup
    if [ ! -e "$HOME/.mozilla/native-messaging-hosts/dl_popup.json" ]; then
        say "Firefox extension: dl-popup"
        sh "$HOME/.local/share/dl-popup/build.sh" || warn "dl-popup Firefox build failed"
    fi
}

# ── systemd + shell ─────────────────────────────────────────────────────────
do_system() {
    say "systemd user units"
    # Ubuntu auto-starts these; in this setup Hyprland's exec-once owns them
    systemctl --user mask hyprpaper.service hypridle.service mako.service waybar.service || true
    systemctl --user daemon-reload
    systemctl --user enable --now aria2.service || warn "aria2.service did not start"
    systemctl --user enable --now tasks-checkin.timer || true
    systemctl --user enable --now tasks-deadlines.timer || true
    if [ "$(getent passwd "$USER" | cut -d: -f7)" != "$(command -v zsh)" ]; then
        say "making zsh the login shell"
        chsh -s "$(command -v zsh)" || warn "chsh failed; run: chsh -s $(command -v zsh)"
    fi
}

do_wallpapers() {
    say "wallpapers"
    bash "$REPO/wallpapers/fetch.sh"
}

case "${1:-all}" in
    packages)   do_packages ;;
    build)      do_build ;;
    copy)       do_copy ;;
    system)     do_system ;;
    wallpapers) do_wallpapers ;;
    all)        do_packages; do_build; do_copy; do_system; do_wallpapers
                say "done — log out and pick Hyprland at the login screen" ;;
    *)          sed -n '2,16p' "$0"; exit 1 ;;
esac
