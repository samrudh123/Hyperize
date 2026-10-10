#!/bin/sh
# File picker for xdg-desktop-portal-termfilechooser: yazi in a floating ghostty.
# Same as the upstream yazi-wrapper.sh except for the terminal line:
#   --gtk-single-instance=false  a plain `ghostty` hands off to the running
#       instance and returns at once, which the portal reads as "cancelled"
#       (same trap documented in ~/.config/hypr/yazi-terminal.sh)
#   --class=com.samrudh.filepicker  Hyprland floats/centres it by this class
#
# Args from the portal: multiple directory save path out debug
# Open:  Enter / Space-select then Enter picks; q quits = cancel.
# Save:  the portal pre-creates the suggested file; hover it and press Enter.
#        To save elsewhere, go to that folder and press Enter on ANY file in it:
#        the download lands there under its own name (never overwriting the
#        file you pressed Enter on — a clash gets "name(1).ext", like Firefox).
#        Moving/renaming the pre-created file and picking it still works, for
#        when you want a different name.
# The portal is started by D-Bus with a bare PATH that lacks ~/.local/bin,
# where yazi (and tools its previewers/openers call) live.
export PATH="$HOME/.local/bin:$PATH"

multiple="$1"; directory="$2"; save="$3"; path="$4"; out="$5"; debug="$6"
set -e
[ "$debug" = 1 ] && set -x

if [ "$save" = 1 ] || [ "$directory" != 1 ]; then
    set -- --chooser-file="$out" "$path"
else
    set -- --chooser-file="$out" --cwd-file="$out.1" "$path"
fi

ghostty --gtk-single-instance=false --class=com.samrudh.filepicker \
    --title="Pick a file" -e "$HOME/.local/bin/yazi" "$@"

if [ "$directory" = 1 ]; then
    if [ ! -s "$out" ] && [ -s "$out.1" ]; then cat "$out.1" > "$out"; fi
    rm -f "$out.1"
fi

# Save mode: Enter on some other file means "save into this file's folder",
# not "overwrite this file". The portal insists the returned file exists and
# deletes its pre-created one ($path) when a different file comes back, so move
# that file into the chosen folder and return the new path.
if [ "$save" = 1 ] && [ -s "$out" ]; then
    chosen=$(head -n1 "$out")
    marker='* xdg-desktop-portal-termfilechooser instructions *'
    # $path itself, or $path moved/renamed in yazi (still holds the portal's
    # instructions text): the user meant exactly that file, leave it alone.
    if [ "$chosen" != "$path" ] && [ "$(head -n1 "$chosen" 2>/dev/null)" != "$marker" ]; then
        if [ -d "$chosen" ]; then dir=$chosen; else dir=$(dirname "$chosen"); fi
        name=$(basename "$path")
        # The portal appends "_" until the pre-created name is free, so a
        # second foo.pdf in its start folder arrives as foo.pdf_ — drop that.
        while [ "${name%_}" != "$name" ] && [ -e "$(dirname "$path")/${name%_}" ]; do
            name=${name%_}
        done
        case "$name" in
            ?*.*) stem=${name%.*}; ext=.${name##*.} ;;
            *)    stem=$name; ext= ;;
        esac
        target="$dir/$name"; n=1
        while [ -e "$target" ]; do
            target="$dir/$stem($n)$ext"; n=$((n + 1))
        done
        if [ -e "$path" ]; then mv "$path" "$target"; else : > "$target"; fi
        printf '%s\n' "$target" > "$out"
    fi
fi
