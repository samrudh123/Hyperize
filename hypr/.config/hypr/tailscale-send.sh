#!/bin/bash
# Send files to another machine on the tailnet with Taildrop — the Tailscale
# pill's "Send files…". They land in the receiver's Taildrop inbox (Android:
# Downloads; Linux: `tailscale file get`).
#
#   tailscale-send.sh HOST [FILE…]      no FILE = pick in yazi
host="$1"; shift
[ -n "$host" ] || { echo "usage: $0 HOST [FILE…]" >&2; exit 2; }
if [ $# -eq 0 ]; then
    mapfile -t files < <("$HOME/.config/hypr/pick-files.sh")
else
    files=("$@")
fi
[ ${#files[@]} -gt 0 ] || exit 0
name="${host%%.*}"
notify-send -a Tailscale -i network-vpn "Sending ${#files[@]} file(s) to $name" "$(printf '%s\n' "${files[@]##*/}" | head -6)"
if err="$(tailscale file cp "${files[@]}" "$host:" 2>&1)"; then
    notify-send -a Tailscale -i network-vpn "Sent to $name" "$(printf '%s\n' "${files[@]##*/}" | head -6)"
else
    notify-send -a Tailscale -i dialog-error "Couldn't send to $name" "$err"
fi
