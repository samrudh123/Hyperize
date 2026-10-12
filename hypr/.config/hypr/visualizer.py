#!/usr/bin/python3
"""Audio visualizer feed for the bottom bar (Visualizer.qml).

    visualizer.py [BARS]     one line per frame (~30 fps): BARS integers 0–100

Records what the speakers play — the default sink's monitor, through
`pw-record` with stream.capture.sink — so no extra package (cava) is needed.
A sink monitor is not a microphone: MicPill's privacy light ignores it.

Log-spaced bands from 50 Hz to 12 kHz, an automatic gain that follows the
loudest recent frame, quick rise / slow fall. Silence prints one line of
zeros and then nothing until sound comes back, so an idle bar costs nothing.
The bar runs this only while a laptop player is playing.
"""

import ctypes
import os
import signal
import subprocess
import sys

os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")   # one tiny matmul a frame:
os.environ.setdefault("OMP_NUM_THREADS", "1")        # no thread pool spinning
import numpy as np

RATE, HOP, WIN = 48000, 1600, 2048        # 30 frames/s, ~43 ms window
BARS = int(sys.argv[1]) if len(sys.argv) > 1 else 12
LO, HI = 50, 12000


def die_with_parent():
    ctypes.CDLL("libc.so.6", use_errno=True).prctl(1, signal.SIGTERM)  # PR_SET_PDEATHSIG


die_with_parent()
rec = subprocess.Popen(
    ["pw-record", "--raw", "--format", "f32", "--rate", str(RATE), "--channels", "1",
     "--latency", "20ms"] + (["--target", os.environ["VIS_TARGET"]] if os.environ.get("VIS_TARGET") else []) + [
     "-P", "{ stream.capture.sink = true, node.name = qs-visualizer, "
           "node.description = \"Bar visualizer\", media.role = Visualizer }", "-"],
    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, preexec_fn=die_with_parent)

freqs = np.fft.rfftfreq(WIN, 1 / RATE)
edges = np.geomspace(LO, HI, BARS + 1)
bands = [np.where((freqs >= edges[i]) & (freqs < edges[i + 1]))[0] for i in range(BARS)]
# the lowest bands are narrower than one FFT bin: give each at least its nearest bin
bands = [b if len(b) else np.array([np.argmin(np.abs(freqs - (edges[i] + edges[i + 1]) / 2))])
         for i, b in enumerate(bands)]
# band powers as one matrix product: row i averages the bins of band i
M = np.zeros((BARS, len(freqs)), np.float32)
for i, b in enumerate(bands):
    M[i, b] = 1 / len(b)
tilt = np.linspace(1, 3, BARS)                    # gentle, so treble isn't always flat
window = np.hanning(WIN).astype(np.float32)
buf = np.zeros(WIN, np.float32)
level = np.zeros(BARS)
peak = 1e-3
quiet = 0

try:
    while True:
        raw = rec.stdout.read(HOP * 4)
        if len(raw) < HOP * 4:
            break
        buf[:-HOP] = buf[HOP:]
        buf[-HOP:] = np.frombuffer(raw, np.float32)
        spec = np.fft.rfft(buf * window)
        vals = np.sqrt(M @ (spec.real ** 2 + spec.imag ** 2)) * tilt
        loud = vals.max()
        peak = max(loud, peak * 0.995, 1e-3)          # AGC: ~5 s to fall by 2/3
        target = np.clip(vals / peak, 0, 1) ** 0.7
        level = np.where(target > level, target, level * 0.82)
        if loud < 1e-3:
            quiet += 1
            if quiet > 15:                            # half a second of silence
                if quiet == 16:
                    print(" ".join(["0"] * BARS), flush=True)
                continue
        else:
            quiet = 0
        print(" ".join(str(int(v * 100)) for v in level), flush=True)
except (BrokenPipeError, KeyboardInterrupt):
    pass
finally:
    rec.terminate()
