#!/usr/bin/python3 -I
"""Run a TUI with Shift+mouse-wheel turned into horizontal wheel events.

    yazi-shiftwheel.py PROGRAM [ARGS…]      (yazi-live.sh runs yazi through it)

yazi scrolls its preview sideways on horizontal wheel events (Preview:touch in
init.lua → plugins/hscroll.yazi), but it never sees Shift+wheel as one: Ghostty
reports Shift+wheel as the vertical wheel button with the shift bit set
(SGR 68/69), and yazi drops mouse modifiers, so it arrives as a plain
vertical scroll. There is no setting for this in either program.

So this sits between the terminal and the program on a pty and rewrites just
those two reports on the way in — Shift+wheel-up → wheel-left (66),
Shift+wheel-down → wheel-right (67). Everything else (keys, clicks, terminal
query replies, and all output, kitty images included) is passed through
byte for byte; the window size (with its pixel size, which image previews
need) is copied to the pty on every resize. Without a terminal on stdin it
just execs the program.
"""
import errno
import fcntl
import os
import pty
import re
import select
import signal
import sys
import termios
import tty

# SGR mouse report: ESC [ < button ; col ; row (M|m)
REPORT = re.compile(rb"\x1b\[<(\d+);")
# a report (or any CSI) cut off at the end of a read — held for the next one
PARTIAL = re.compile(rb"\x1b(\[(<[\d;]*)?)?$")


def swap(m):
    b = int(m.group(1))
    # 64/65 = wheel up/down, +4 = shift (other modifier bits are left alone)
    if b & 0b11000011 in (64, 65) and b & 4:
        b = (b - 4) + 2                     # → 66/67, horizontal, shift cleared
    return b"\x1b[<%d;" % b


def copy_size(src, dst):
    try:
        fcntl.ioctl(dst, termios.TIOCSWINSZ, fcntl.ioctl(src, termios.TIOCGWINSZ, b"\0" * 8))
    except OSError:
        pass


def write_all(fd, data):
    while data:
        try:
            data = data[os.write(fd, data):]
        except InterruptedError:
            continue


def main():
    argv = sys.argv[1:]
    if not argv:
        sys.exit("usage: yazi-shiftwheel.py PROGRAM [ARGS…]")
    if not os.isatty(0):
        os.execvp(argv[0], argv)

    pid, master = pty.fork()
    if pid == 0:
        os.execvp(argv[0], argv)

    copy_size(0, master)
    # the kernel sends SIGWINCH to the program when the pty's size changes
    signal.signal(signal.SIGWINCH, lambda *_: copy_size(0, master))

    saved = termios.tcgetattr(0)
    tty.setraw(0)
    carry = b""
    try:
        while True:
            try:
                # a held fragment is flushed after 30 ms, so a lone Esc key
                # press is never delayed noticeably
                ready, _, _ = select.select([0, master], [], [], 0.03 if carry else None)
            except InterruptedError:
                continue
            if not ready and carry:
                write_all(master, carry)
                carry = b""
                continue
            if master in ready:
                try:
                    out = os.read(master, 65536)
                except OSError as e:
                    if e.errno == errno.EIO:     # program exited, pty closed
                        break
                    raise
                if not out:
                    break
                write_all(1, out)
            if 0 in ready:
                data = carry + os.read(0, 65536)
                if not data:
                    break
                m = PARTIAL.search(data)
                data, carry = (data[:m.start()], data[m.start():]) if m else (data, b"")
                if data:
                    write_all(master, REPORT.sub(swap, data))
    finally:
        termios.tcsetattr(0, termios.TCSAFLUSH, saved)

    _, status = os.waitpid(pid, 0)
    sys.exit(os.waitstatus_to_exitcode(status) if hasattr(os, "waitstatus_to_exitcode") else 0)


if __name__ == "__main__":
    main()
