"""Long-running mode for the bar's polled status scripts.

A ScriptPill polling `foo.py status` every 2 s started a fresh python3 each
time — ~60-110 ms of CPU per run, mostly interpreter start-up and imports,
for output that rarely changes (measured 2026-10-24: four such pills cost
~14% of a core). `barwatch.run(status)` keeps one process instead: it calls
the same status function on the same interval, in-process, and prints a line
only when it changed. SIGUSR1 polls right away — ScriptPill's `pokable` sends
it after a click, so the pill still reflects the click at once.

The status function prints its JSON line exactly as in `status` mode, so the
two can never drift apart.
"""

import contextlib
import ctypes
import io
import signal
import sys


def die_with_parent():
    """SIGTERM us when the parent (Quickshell) exits. A watcher that only
    prints on change never hits a broken pipe, so without this it outlives a
    Quickshell restart forever."""
    ctypes.CDLL("libc.so.6", use_errno=True).prctl(1, signal.SIGTERM)   # PR_SET_PDEATHSIG


def run(status, interval, error=None):
    """Call status() every `interval` seconds; print its last line on change.

    error(exc) -> the line to show if status() raises (default: keep the last
    one); the loop itself never dies over it.
    """
    die_with_parent()
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    # SIGUSR1 stays blocked and is only ever taken by sigtimedwait() below: a
    # poke that lands mid-poll waits there, so none is lost and no handler
    # races the loop.
    signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGUSR1})
    last = None
    while True:
        buf = io.StringIO()
        try:
            with contextlib.redirect_stdout(buf):
                status()
            lines = buf.getvalue().strip().splitlines()
            line = lines[-1] if lines else ""
        except Exception as exc:                    # noqa: BLE001
            line = error(exc) if error else last
        if line and line != last:
            try:
                print(line, flush=True)
            except BrokenPipeError:
                return
            last = line
        signal.sigtimedwait({signal.SIGUSR1}, interval)
