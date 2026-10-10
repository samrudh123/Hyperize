#!/bin/bash
# Start yazi with ~/.local/bin on PATH.
#
# The Hyprland session's PATH has no ~/.local/bin (only .zshrc adds it), and
# `ghostty -e` runs its command directly, not through a shell. yazi itself was
# found by absolute path, but everything yazi spawns by name was not — notably
# `ya`, which the built-in "Extract here" opener runs (`ya pub extract`), so
# extracting failed with "ya: not found" and left the task stuck as "1 left".
export PATH="$HOME/.local/bin:$PATH"
exec "$HOME/.local/bin/yazi" "$@"
