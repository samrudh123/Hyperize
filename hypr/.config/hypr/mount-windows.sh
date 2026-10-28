#!/bin/bash
# Unlock and mount the BitLocker Windows partition — entirely in user space.
#
# No root, no /etc/crypttab, no /etc/fstab: udisks2 + polkit already let the
# console user unlock and mount a volume, which is exactly what Files does when
# you click the drive. This just does it without the clicking.
#
#   --boot    for exec-once. Never prompts and is silent, so a missing or wrong
#             passphrase can never hold up a login. Retries longest, because at
#             login it can beat udisks2, polkit and the keyring to being ready.
#   --ensure  same never-prompt, never-speak policy, but only a couple of
#             retries. For "mount it in the background if you can" callers
#             (SUPER+E) that must not delay the thing you actually asked for.
#   --open    ensure it is mounted (prompting on the terminal if no passphrase
#             is stored anywhere), then open it in yazi.
#   (none)    ensure it is mounted, prompting if needed, and print the mount
#             point. This is the mode for `gw` inside yazi.
#
# ── Where the passphrase comes from ──────────────────────────────────────────
# Unattended unlocking needs the passphrase retrievable without you. Two
# sources are tried, most secure first. This script never asks you to hand it
# the passphrase, and never writes it to a disk.
#
#   1. The login keyring (preferred). Encrypted at rest with your login
#      password, and unlocked for you by pam_gnome_keyring at the GDM prompt.
#      Store it once, yourself:
#
#        secret-tool store --label='BitLocker Windows volume' \
#            bitlocker-uuid <uuid>
#
#      <uuid> is the partition's, as `lsblk -o NAME,FSTYPE,UUID` shows it
#      (the row whose FSTYPE is BitLocker).
#
#      (needs `libsecret-tools`; it prompts with echo off and stores nothing
#      in your shell history.)
#
#   2. ~/.config/hypr/.windows-key, mode 600 — plaintext, for machines with no
#      keyring. Kept as a fallback:
#
#        printf '%s' 'your-bitlocker-password' > ~/.config/hypr/.windows-key
#        chmod 600 ~/.config/hypr/.windows-key
#
# Understand what option 2 costs: **/ and /home on this machine are plain ext4,
# not encrypted.** A passphrase sitting in $HOME is therefore readable by
# anyone who takes the disk out, which reduces BitLocker to roughly no
# protection at rest. The keyring does not have that problem — pulling the disk
# out yields a file encrypted with your login password. Prefer option 1.
#
# With neither source, every mode still works: the interactive ones ask once
# per boot and the unattended ones quietly do nothing.
#
# ── Dual-boot warning ────────────────────────────────────────────────────────
# If Windows Fast Startup or hibernation is enabled, the NTFS is left dirty and
# writing to it from Linux can corrupt it. The ntfs driver normally refuses a
# read-write mount in that state — if a mount fails complaining about
# hibernation, that is the guard working. Turn Fast Startup off in Windows
# rather than forcing the mount.

set -u

# The BitLocker partition: $WINDOWS_UUID if set, else the first BitLocker
# volume lsblk lists (it reads udev's database — no `disk` group needed).
UUID="${WINDOWS_UUID:-$(lsblk -rno UUID,FSTYPE 2>/dev/null | awk '$2 == "BitLocker" { print $1; exit }')}"
DEV="/dev/disk/by-uuid/$UUID"
KEYFILE="$HOME/.config/hypr/.windows-key"
MOUNTPOINT="/run/media/$USER/Windows"
MODE="${1:-}"

RUNDIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
[ -w "$RUNDIR" ] || RUNDIR="${TMPDIR:-/tmp}"

# Absolute path on purpose: keybind children do NOT get ~/.local/bin on PATH,
# so a bare `yazi` dies with "not found" the moment this runs from a bind.
YAZI="$HOME/.local/bin/yazi"
[ -x "$YAZI" ] || YAZI="$(command -v yazi 2>/dev/null)"

# --boot and --ensure are the unattended callers: no prompting, no output.
# Three separate keybinds reach this script now, and two of them fire without
# you asking for the drive, so anything chatty would be noise on every login.
case "$MODE" in
    --boot)   UNATTENDED=1; TRIES=5 ;;
    --ensure) UNATTENDED=1; TRIES=2 ;;
    *)        UNATTENDED=0; TRIES=1 ;;
esac

note() { [ "$UNATTENDED" = 1 ] || printf '%s\n' "$*"; }
fail() { [ "$UNATTENDED" = 1 ] || printf '%s\n' "$*" >&2; }

mounted() { findmnt -rno TARGET "$MOUNTPOINT" >/dev/null 2>&1; }

# What the caller wanted, once the volume is there. Both non-silent modes end
# here, so there is exactly one place that knows what each mode returns.
deliver() {
    exec 9>&-                               # don't leak the lock fd into yazi
    case "$MODE" in
        --open) exec "$YAZI" "$MOUNTPOINT" ;;
        "")     printf '%s\n' "$MOUNTPOINT" ;;
    esac
    exit 0
}

# ── Serialise ────────────────────────────────────────────────────────────────
# SUPER+E now fires --ensure in the background, so pressing `gw` a second later
# can land a second instance mid-unlock. Two concurrent `udisksctl unlock` calls
# on one device is how you get a spurious failure on the loser. The lock is held
# only across unlock+mount and dropped before yazi runs — otherwise a yazi left
# open for an hour would block every other caller.
exec 9>"$RUNDIR/mount-windows.lock"
# A timeout is not fatal: 60s means the other holder is wedged, and trying
# unserialised is more useful than refusing to mount at all.
flock -w 60 9 2>/dev/null || fail "Another mount attempt is still running; trying anyway."

# Already mounted? Nothing to do.
if mounted; then
    note "Already mounted at $MOUNTPOINT"
    flock -u 9
    deliver
fi

[ -b "$(readlink -f "$DEV")" ] || { fail "Windows partition not found ($DEV)"; exit 1; }

# The unlocked volume appears as a "holder" of the partition in sysfs.
# Read it from there rather than with `lsblk <device>`: lsblk has to open the
# device node, this user is not in the `disk` group, and it then prints NOTHING
# at all while still exiting 0 — a silent empty result, not an error.
cleartext() {
    local part holder
    part="$(basename "$(readlink -f "$DEV")")"
    for holder in "/sys/class/block/$part/holders/"*; do
        [ -e "$holder" ] || continue
        printf '/dev/%s\n' "$(basename "$holder")"
        return
    done
}

# Is there any source that could ever yield a passphrase? Used to decide
# whether retrying is worth it: a locked or slow keyring is worth waiting for at
# login, a machine with neither source is not.
key_source_possible() {
    command -v secret-tool >/dev/null 2>&1 || [ -r "$KEYFILE" ]
}

# Keyring first, key file second. The command substitution strips trailing
# newlines, which is deliberate: it makes a key file created with `echo`
# instead of `printf` work, and neither source stores a meaningful one.
read_key() {
    local k=""
    if command -v secret-tool >/dev/null 2>&1; then
        # `timeout` is not paranoia: if the login keyring is locked (its
        # password diverged from your login password, so pam_gnome_keyring
        # could not open it), secret-tool does not fail — it BLOCKS waiting for
        # a gcr-prompter GUI that may never appear. Unbounded, that hangs the
        # retry loop instead of falling through to the key file or a tty prompt.
        k="$(timeout 10 secret-tool lookup bitlocker-uuid "$UUID" 2>/dev/null)"
    fi
    if [ -z "$k" ] && [ -r "$KEYFILE" ]; then
        k="$(cat "$KEYFILE")"
    fi
    [ -n "$k" ] || return 1
    printf '%s' "$k"
}

if [ -z "$(cleartext)" ]; then
    if ! key_source_possible && [ "$UNATTENDED" = 1 ]; then
        exit 0                                  # nothing to try; stay silent
    fi

    # udisksctl takes the passphrase from a FILE and nothing else, so a keyring
    # secret has to be staged as one. $XDG_RUNTIME_DIR is tmpfs (never written
    # to a disk) and mode 0700 (no other user can open it); mktemp gives 0600.
    # The trap removes it on every exit path, signals included.
    TMPKEY=""
    trap '[ -n "$TMPKEY" ] && rm -f "$TMPKEY"' EXIT HUP INT TERM
    TMPKEY="$(mktemp "$RUNDIR/.wkey.XXXXXX")" || { fail "Cannot stage the key."; exit 1; }

    had_key=0
    n=0
    while :; do
        n=$((n+1))

        if key="$(read_key)"; then
            had_key=1
            printf '%s' "$key" > "$TMPKEY"
            unset key
            udisksctl unlock -b "$DEV" --key-file "$TMPKEY" >/dev/null 2>&1 && break
        elif [ "$UNATTENDED" = 0 ]; then
            # udisksctl prompts on the terminal with echo off. Nothing is
            # written to disk, and this script never sees the passphrase.
            note "No stored passphrase; unlocking interactively."
            udisksctl unlock -b "$DEV" || { fail "Unlock cancelled or failed"; exit 1; }
            break
        fi

        [ -n "$(cleartext)" ] && break          # someone else unlocked it

        if [ "$n" -ge "$TRIES" ]; then
            if [ "$had_key" = 1 ]; then
                fail "Unlock failed — is the stored passphrase correct?"
            else
                fail "No passphrase available (keyring locked or empty?)."
            fi
            exit 1
        fi
        sleep 4
    done

    rm -f "$TMPKEY"
    TMPKEY=""
fi

CT="$(cleartext)"
[ -n "$CT" ] || { fail "Unlocked, but no cleartext device appeared"; exit 1; }

udisksctl mount -b "$CT" >/dev/null 2>&1 || {
    # Already-mounted is not an error; anything else is.
    mounted || { fail "Mount failed. If it mentions hibernation, disable Fast Startup in Windows."; exit 1; }
}

note "Mounted at $MOUNTPOINT"
# mount-watch.py notices the new mount and re-runs dock-places.sh, so the disk
# icon appears in the sidebar on its own.

flock -u 9
deliver
