#!/bin/bash
# Open a terminal at a directory — bound to <C-t> in yazi.
#
#   yazi-terminal.sh            open at the caller's cwd
#   yazi-terminal.sh <dir>      open there
#   yazi-terminal.sh <file>     open at the file's parent
#
# yazi substitutes %s with the HOVERED item, which may be a file rather than a
# directory, so resolving the parent here is what makes the bind work no matter
# what the cursor happens to be sitting on. yazi runs `shell` commands with the
# current directory as cwd, so the no-argument case is the right fallback.
#
# --gtk-single-instance=false is deliberate: ghostty is single-instance by
# default, and a second plain `ghostty` invocation is handled by the ALREADY
# RUNNING process — which inherits that instance's working directory and
# silently ignores --working-directory. (Same single-instance behaviour that
# once made a `[workspace 3 silent]` exec rule appear to fail.) A private
# instance costs a little memory and is the only way the directory is honoured.

set -u

target="${1:-}"

if [ -n "$target" ] && [ -d "$target" ]; then
    dir="$target"
elif [ -n "$target" ] && [ -e "$target" ]; then
    dir="$(dirname -- "$target")"
else
    dir="$PWD"
fi

[ -d "$dir" ] || dir="$HOME"

# setsid: the terminal is spawned by yazi, so without a new session it stays in
# yazi's process group and closing yazi can take it down with it.
exec setsid ghostty --gtk-single-instance=false --working-directory="$dir"
