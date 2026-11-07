"""Plain-English names for the Hyprland binds, for Settings › Keybindings ›
Hyprland (settings-keybinds.py).

hyprland.conf's trailing comments ("# downloads (aria2 queue)") and the
generated fallbacks ("Resize window -40 0", "Shell: clipboard toggle") made
poor titles. Each rule here matches a bind by WHAT IT RUNS (dispatcher +
argument), not its keys, so a bind moved to other keys keeps its name, and a
binding of your own that runs the same thing gets the description too. The
technical side (dispatcher, command) is not a title: the panel shows it on the
row's last line.

    doc(dispatcher, arg_raw, arg_expanded, key) → (title, description) | None

Add a rule when you add a bind to hyprland.conf: (dispatcher, regex searched in
the argument — raw, with $vars, then expanded —, title, description). Titles
and descriptions may use the regex's groups as {1}, {2} (a l/r/u/d group as
{dir1} = left/…, {where1} = to the left/…/above/below).
"""

import re

_DIR = {"l": "left", "r": "right", "u": "up", "d": "down"}
_WHERE = {"l": "to the left", "r": "to the right", "u": "above", "d": "below"}

RULES = [
    # ─── apps ────────────────────────────────────────────────────────────────
    ("exec", r"^\$terminal$", "Terminal", "Open a new Ghostty terminal window."),
    ("exec", r"^\$menu$", "App launcher", "Show the grid of installed apps; type to search and open one."),
    ("exec", r"^\$browser$", "Zen Browser", "Open a new window of Zen, your default web browser."),
    ("exec", r"^\$browserAlt$", "Firefox", "Open a new Firefox window."),
    ("exec", r"\$fileMgr$", "File manager (yazi)",
     "Open yazi, the keyboard-driven file manager, in a terminal (the Windows drive is mounted first)."),
    ("exec", r"^nautilus", "Files (Nautilus)", "Open the regular point-and-click file manager in a new window."),
    ("exec", r"^\$editor$", "VS Code", "Open Visual Studio Code."),
    ("exec", r"focus-or-launch\.sh spotify", "Spotify", "Switch to Spotify, or start it if it isn't running."),
    ("exec", r"focus-or-launch\.sh vesktop", "Discord (Vesktop)",
     "Switch to Discord (the Vesktop app), or start it if it isn't running."),
    ("exec", r"focus-or-launch\.sh obsproject", "OBS Studio",
     "Switch to OBS (screen recording and streaming), or start it if it isn't running."),
    ("exec", r"focus-or-launch\.sh kdenlive", "Kdenlive",
     "Switch to the Kdenlive video editor, or start it if it isn't running."),
    ("exec", r"focus-or-launch\.sh (\S+)", "Open {1}", "Switch to {1}, or start it if it isn't running."),
    ("exec", r"^hyprlock$", "Lock screen", "Lock the screen now; type your password to get back in."),

    # ─── shell panels ────────────────────────────────────────────────────────
    ("exec", r"ipc call players toggle", "Media players",
     "Show what's playing on the laptop and the phone, with play / pause, skip and volume."),
    ("exec", r"ipc call news toggle", "News",
     "Open the news panel (the bottom bar's news pill): headlines by category, sub-category chips, and More to add categories."),
    ("exec", r"panels toggle audio", "Sound panel",
     "Open the sound panel (the top bar's volume pill): volume, outputs and inputs, per-app streams."),
    ("exec", r"panels toggle network wifi", "Wi-Fi panel",
     "Open the Wi-Fi panel (the top bar's network pill): connect, forget, scan for networks."),
    ("exec", r"ipc call capture toggle", "Capture panel",
     "Open the capture panel (the top bar's camera pill): screenshots, screen recording, sound source."),
    ("exec", r"ipc call downloads toggle|dl-popup status", "Downloads",
     "Open the downloads panel (the bottom bar's download pill): progress, pause / resume, open finished files."),
    ("exec", r"ipc call display cycle", "Switch display mode",
     "With a second screen plugged in, switch between showing the same picture on both and extending the desktop onto it (like Windows+P)."),
    ("exec", r"ipc call themepicker", "Change theme", "Pick a colour theme for the whole desktop."),
    ("exec", r"ipc call power toggle", "Power menu", "Shut down, restart, sleep, log out or lock."),
    ("exec", r"^hyprpicker", "Copy a colour from the screen",
     "Click any pixel on the screen to copy its colour code (like #89b4fa) to the clipboard."),
    ("exec", r"accent-picker\.py", "Change accent colour",
     "Choose the highlight colour used by the bars, window borders and themed apps."),
    ("exec", r"blur\.sh toggle", "Blur on / off",
     "Turn the frosted-glass blur behind see-through windows and panels on or off (off saves battery)."),
    ("exec", r"tasks\.py toggle", "To-do list", "Show or hide the tasks panel with your to-dos and deadlines."),
    ("exec", r"ipc call wspicker", "Workspace overview",
     "Show every workspace as a card with live previews; pick one to go there."),
    ("exec", r"panels toggle notifications", "Notification centre",
     "Show recent notifications and the Do Not Disturb switch."),
    ("exec", r"panels nav start", "Open top-bar panels with keyboard",
     "Open the sound panel and move through the top bar's panels with the keyboard: Tab / arrows / Enter inside, Ctrl+arrows to the next panel. Press again to close."),
    ("exec", r"dismiss-reminders\.sh", "Dismiss task reminders",
     "Close the task reminder pop-ups on screen. Escape still works normally in the app you're in."),
    ("exec", r"dock-toggle\.sh", "Show / hide dock", "Show or hide the app dock."),
    ("exec", r"wallpicker toggle desktop", "Change wallpaper", "Browse your wallpapers and set the desktop background."),
    ("exec", r"wallpicker toggle lock", "Change lock screen picture", "Pick the picture shown behind the lock screen."),
    ("global", r"quickshell:settings", "Settings", "Open this Settings window."),
    ("exec", r"CHEATSHEET\.md", "Shortcut cheat sheet", "Show the list of all keyboard shortcuts in a terminal."),
    ("exec", r"ipc call clipboard toggle", "Clipboard history",
     "Show what you copied recently (text and images) and paste one again."),

    # ─── focus / move / resize / workspaces ──────────────────────────────────
    ("exec", r"focus-dir\.py ([lrud])", "Focus window {dir1}",
     "Move the keyboard focus to the window {where1} (floating pop-ups included)."),
    ("movewindow", r"^([lrud])$", "Move window {dir1}",
     "Move the focused window {dir1}, swapping places with the window there."),
    ("resizeactive", r"^-\d+\s+0$", "Make window narrower", "Shrink the focused window's width a little (40 px)."),
    ("resizeactive", r"^\d+\s+0$", "Make window wider", "Grow the focused window's width a little (40 px)."),
    ("resizeactive", r"^0\s+-\d+$", "Make window shorter", "Shrink the focused window's height a little (40 px)."),
    ("resizeactive", r"^0\s+\d+$", "Make window taller", "Grow the focused window's height a little (40 px)."),
    ("workspace", r"^(\d+)$", "Go to workspace {1}", "Switch to workspace {1}."),
    ("movetoworkspace", r"^(\d+)$", "Send window to workspace {1}",
     "Move the focused window to workspace {1} and go there with it."),
    ("togglespecialworkspace", r"", "Show / hide scratchpad",
     "A hidden extra workspace that slides over the current one: keep a terminal or notes there, on call."),
    ("movetoworkspace", r"^special", "Send window to scratchpad",
     "Move the focused window to the hidden scratchpad workspace (Super+S brings it back)."),
    ("exec", r"workspace-scroll\.sh next", "Next workspace", "Hold Super and scroll to go to the next workspace."),
    ("exec", r"workspace-scroll\.sh prev", "Previous workspace",
     "Hold Super and scroll to go to the previous workspace."),

    # ─── windows ─────────────────────────────────────────────────────────────
    ("killactive", r"", "Close window", "Close the focused window, like clicking its ✕."),
    ("exit", r"", "Log out", "Leave the desktop session: closes every app and quits Hyprland."),
    ("togglefloating", r"", "Float / tile window",
     "Switch the focused window between tiled (fills its slot) and floating (free size and position)."),
    ("fullscreen", r"^1$", "Maximise", "Make the focused window fill the screen, keeping the bars."),
    ("fullscreen", r"", "Fullscreen", "Make the focused window cover the whole screen, bars included."),
    ("pseudo", r"", "Keep window's own size",
     "The focused window keeps the size it asked for, centred in its tile, instead of stretching to fill it."),
    ("togglesplit", r"", "Rotate split",
     "Flip how this window shares its space with its neighbour: side by side ↔ one above the other."),
    ("exec", r"opacity\.sh up", "Make window more solid",
     "Hold Super+Shift and scroll to make the window under the cursor less see-through."),
    ("exec", r"opacity\.sh down", "Make window more see-through",
     "Hold Super+Shift and scroll to make the window under the cursor more transparent."),
    ("exec", r"opacity\.sh reset", "Reset window transparency",
     "Super+Shift+middle-click puts the window back to its usual transparency."),

    # ─── screenshots ─────────────────────────────────────────────────────────
    ("exec", r"screenshot\.sh region", "Screenshot an area",
     "Drag a box around part of the screen; the picture is copied, then you choose whether to save it."),
    ("exec", r"screenshot\.sh screen", "Screenshot the screen",
     "Capture the whole screen; the picture is copied, then you choose whether to save it."),
    ("exec", r"screenshot\.sh window", "Screenshot a window",
     "Click a window to capture it; the picture is copied, then you choose whether to save it."),

    # ─── laptop keys ─────────────────────────────────────────────────────────
    ("exec", r"wpctl set-volume .*5%\+", "Volume up", "Raise the speaker volume by 5% (up to 140%)."),
    ("exec", r"wpctl set-volume .*5%-", "Volume down", "Lower the speaker volume by 5%."),
    ("exec", r"wpctl set-mute @DEFAULT_AUDIO_SINK@", "Mute / unmute sound", "Turn the speakers off or back on."),
    ("exec", r"wpctl set-mute @DEFAULT_AUDIO_SOURCE@", "Mute / unmute microphone",
     "Turn the microphone off or back on."),
    ("exec", r"brightness\.sh up", "Brightness up", "Make the screen brighter by 5%."),
    ("exec", r"brightness\.sh down", "Brightness down", "Make the screen dimmer by 5%."),
    ("exec", r"playerctl next", "Next track", "Skip to the next song or video in the active player."),
    ("exec", r"playerctl previous", "Previous track", "Go back to the previous song or video."),
    ("exec", r"playerctl play-pause", "Play / pause", "Play or pause whatever is playing."),
]

# mouse drags (bindm) — the dispatchers mean something else there
MOUSE = {
    "movewindow": ("Drag to move window", "Hold Super and drag a window with the left mouse button to move it."),
    "resizewindow": ("Drag to resize window", "Hold Super and drag with the right mouse button to resize a window."),
}


def _fill(s, m):
    for i, g in enumerate(m.groups() if m else (), 1):
        s = (s.replace("{dir%d}" % i, _DIR.get(g, g)).replace("{where%d}" % i, _WHERE.get(g, g))
             .replace("{%d}" % i, g))
    return s


def doc(dispatcher, arg_raw, arg_expanded, key="", kind="bind"):
    """(title, description) for a bind, or None"""
    if kind == "bindm" and dispatcher in MOUSE:
        return MOUSE[dispatcher]
    if key.startswith("switch:") and "Lid" in key and "hyprlock" in arg_expanded:
        return ("Lock when the lid closes", "Closing the laptop lid locks the screen.")
    for disp, pat, title, about in RULES:
        if disp != dispatcher:
            continue
        for arg in (arg_raw.strip(), arg_expanded.strip()):
            m = re.search(pat, arg)
            if m:
                return _fill(title, m), _fill(about, m)
    return None
