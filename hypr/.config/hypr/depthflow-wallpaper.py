"""Render a looping 2.5D parallax video from a still wallpaper with DepthFlow.

Run with DepthFlow's own interpreter (installed via `uv tool install depthflow`):

    ~/.local/share/uv/tools/depthflow/bin/python ~/.config/hypr/depthflow-wallpaper.py \
        [drift|sway|breathe] input -i IMAGE main -o OUT.mp4 -w 1920 -h 1200 -t 20

The first word picks the motion (default: drift). Everything after it is passed
to DepthFlow's CLI unchanged. All motions use self.cycle (0..2pi over the video
length), so the last frame meets the first and the video loops seamlessly.
"""

import math
import sys

from attrs import define
from depthflow.scene import DepthScene


@define
class Drift(DepthScene):
    """Slow, small circle: the camera floats. Calm enough to sit behind windows."""
    def update(self):
        self.state.height = 0.18
        self.state.steady = 0.30
        self.state.isometric = 0.60
        self.state.zoom = 1.00
        self.state.offset = (
            0.25 * math.cos(self.cycle),
            0.15 * math.sin(self.cycle),
        )


@define
class Sway(DepthScene):
    """Side-to-side only, a little stronger than drift."""
    def update(self):
        self.state.height = 0.20
        self.state.steady = 0.30
        self.state.isometric = 0.60
        self.state.zoom = 1.00
        self.state.offset = (0.40 * math.sin(self.cycle), 0.0)


@define
class Breathe(DepthScene):
    """Gentle push in and out towards the subject."""
    def update(self):
        self.state.steady = 0.30
        self.state.focus = 0.30
        self.state.zoom = 1.00
        self.state.height = 0.10 + 0.12 * (1.0 - math.cos(self.cycle)) / 2.0


SCENES = {"drift": Drift, "sway": Sway, "breathe": Breathe}

if __name__ == "__main__":
    args = sys.argv[1:]
    name = args.pop(0) if args and args[0] in SCENES else "drift"
    SCENES[name]().cli.meta(args)
