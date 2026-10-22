#!/usr/bin/python3
"""Claude Code in the desktop's colours: writes ~/.claude/themes/rice.json.

Called by set-accent.sh (reload_apps) on every committed accent / theme change.
Claude Code watches ~/.claude/themes/ and reloads a changed theme file in
running sessions, so open sessions recolour without a restart. Selected with
"theme": "custom:rice" in ~/.claude/settings.json (or /theme → Rice).

Same split as the rest of the rice: the ACCENT goes on Claude Code's own
chrome (brand colour + spinner, dialog borders, picker highlight, selection,
a faint tint on your messages); status and diff colours stay on the theme's
roles (green / red / yellow …) so they keep their meaning.

Colours come from theme/palette.json (set-theme.sh) and theme/accent
(set-accent.sh), like the Quickshell shell and Neovim's rice colorscheme.
"""

import json
import os

THEME = os.path.expanduser("~/.config/hypr/theme")
OUT = os.path.expanduser("~/.claude/themes/rice.json")

# Catppuccin Mocha, if the theme state is missing
MOCHA = dict(zip(
    "rosewater flamingo pink mauve red maroon peach yellow green teal sky sapphire blue "
    "lavender text subtext1 subtext0 overlay2 overlay1 overlay0 surface2 surface1 surface0 "
    "base mantle crust".split(),
    ["#" + h for h in "f5e0dc f2cdcd f5c2e7 cba6f7 f38ba8 eba0ac fab387 f9e2af a6e3a1 94e2d5 "
     "89dceb 74c7ec 89b4fa b4befe cdd6f4 bac2de a6adc8 9399b2 7f849c 6c7086 585b70 45475a "
     "313244 1e1e2e 181825 11111b".split()]))


def load():
    try:
        with open(os.path.join(THEME, "palette.json")) as f:
            p = json.load(f)
        if "base" not in p:
            raise ValueError
    except (OSError, ValueError):
        p = dict(MOCHA, name="Catppuccin Mocha", accent="mauve")
    try:
        with open(os.path.join(THEME, "accent")) as f:
            h = f.read().strip().lstrip("#").lower()
        int(h, 16)
        accent = "#" + h if len(h) == 6 else None
    except (OSError, ValueError):
        accent = None
    return p, accent or p.get(p.get("accent", "mauve"), p["mauve"])


def blend(fg, bg, a):
    """fg mixed over bg, a = share of fg"""
    f = [int(fg[i:i + 2], 16) for i in (1, 3, 5)]
    b = [int(bg[i:i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{round(x * a + y * (1 - a)):02x}" for x, y in zip(f, b))


def main():
    p, A = load()
    base = p["base"]
    o = {
        # Claude Code's own chrome — the accent
        "claude": A,
        "claudeShimmer": blend(A, p["text"], 0.6),
        "clawd_body": A,
        "permission": A,
        "permissionShimmer": blend(A, p["text"], 0.6),
        "suggestion": A,
        "promptBorder": blend(A, p["surface1"], 0.45),
        "promptBorderShimmer": A,
        "selectionBg": blend(A, base, 0.35),
        "userMessageBackground": blend(A, base, 0.08),
        "userMessageBackgroundHover": blend(A, base, 0.14),
        "fastMode": A,
        "fastModeShimmer": blend(A, p["text"], 0.6),
        # text
        "text": p["text"],
        "inverseText": p["crust"],
        "inactive": p["overlay1"],
        "inactiveShimmer": p["subtext0"],
        "subtle": p["surface2"],
        # meaning-carrying colours stay on their roles
        "success": p["green"],
        "error": p["red"],
        "warning": p["yellow"],
        "warningShimmer": blend(p["yellow"], p["text"], 0.6),
        "merged": p["mauve"],
        "remember": p["lavender"],
        "planMode": p["teal"],
        "ide": p["sapphire"],
        "bashMessageBackgroundColor": p["surface0"],
        "memoryBackgroundColor": blend(p["lavender"], base, 0.10),
        "diffAdded": blend(p["green"], base, 0.22),
        "diffRemoved": blend(p["red"], base, 0.22),
        "diffAddedDimmed": blend(p["green"], base, 0.12),
        "diffRemovedDimmed": blend(p["red"], base, 0.12),
        "diffAddedWord": blend(p["green"], base, 0.45),
        "diffRemovedWord": blend(p["red"], base, 0.45),
    }
    theme = {"name": "Rice", "base": "dark", "overrides": o}
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    tmp = OUT + ".tmp"
    with open(tmp, "w") as f:
        json.dump(theme, f, indent=2)
        f.write("\n")
    os.replace(tmp, OUT)   # one complete write, so the watcher never sees half a file


if __name__ == "__main__":
    main()
