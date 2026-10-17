# Hyprland Keys — quick reference

SUPER = the Windows key (bottom-left, between Fn and Alt).
Online version: https://claude.ai/artifact/QtvkUqWFVMf9392AwsNaea

## First five minutes

| Keys | Does |
|---|---|
| `SUPER + Return` | Terminal. Your lifeline. |
| `SUPER + D` | App grid — type to search, Enter; Escape closes |
| `SUPER + Q` | Close the focused window |
| `SUPER + 1..0` | Switch workspace |
| `SUPER + A` | Show / hide the app sidebar (left edge) |
| `SUPER + SHIFT + E` | Quit Hyprland → login screen (escape hatch) |

## Launching

| Keys | Does |
|---|---|
| `SUPER + Return` | Terminal (Ghostty) |
| `SUPER + D` | App grid — icons, search, right-click to pin (nwg-drawer) |
| `SUPER + B` | Brave |
| `SUPER + SHIFT + C` | VS Code |
| `SUPER + SHIFT + M` | Spotify (focus if open, else launch) |
| `SUPER + SHIFT + D` | Discord via Vesktop (focus if open, else launch) |
| `SUPER + O` | OBS Studio (focus if open, else launch) |
| `SUPER + SHIFT + O` | Kdenlive (focus if open, else launch) |
| `SUPER + SHIFT + P` | Players menu — now playing + Spotify / YouTube launchers |
| `SUPER + ALT + D` | Downloads menu — aria2 queue: pause / resume / remove / open, open JDownloader |
| `SUPER + E` | File manager (yazi) — press `q` to quit into that folder |
| `SUPER + ALT + E` | Files (Nautilus) |
| ⤷ in yazi | `Ctrl+T` terminal here · `Ctrl+O` VS Code · `Alt+O` Files · `Alt+G` grid view (thumbnails; `q` back) · `gw` Windows drive · `.` hidden files |
| `SUPER + M` | Windows drive in yazi (unlocks + mounts it if needed) |
| ⤷ the drive | mounts itself at login. `SUPER+M`, `SUPER+E` and `gw` each mount it if it is not already — no passphrase, as long as it is in your keyring |
| `SUPER + A` | Toggle the app sidebar (left edge) |
| ⤷ the sidebar | a centred strip that floats **over** your windows — it no longer reserves the left edge, so showing it does not resize anything |
| ⤷ on an icon | click focuses (again = next window) · middle-click new window · **drag** a pinned icon to reorder · **right-click**: its windows, new window, pin / unpin, close |
| `SUPER + W` | Pick a desktop wallpaper — carousel with colour filters; also sets the accent to the wallpaper's colour (press again to close) |
| ⤷ in the picker | `←/→` or wheel move (mouse wheel up / two-finger down = next) · `Enter` set · `Tab` next filter · `a` all · `v` videos · `1`–`8` colours · `c` accent follows wallpaper on/off · `/` search · `Esc` close |
| ⤷ `t` in the picker | **transition** for wallpaper changes — `←/→` pick (it plays a preview on the real wallpaper behind the picker), `p` replay, `Enter` done. Circle zoom · From cursor · Iris · Fade · Wipe · Wave · Slide · Zoom · Dissolve · Pixelate · Diamond · Random · Instant |
| `SUPER + SHIFT + W` | Pick a lock screen image — the same carousel and colour filters, plus a "Live screen" card (blur whatever is on screen). Accent-follows starts off here (`c`) |
| Tasks icon (bottom bar, centre) | Tasks panel: **Remaining**, **Done today**, **Log**, and a **History** tab of past days. Shows how many tasks are left |
| ⤷ in the panel | Enter adds · tick to finish · double-click or ✎ to edit · ↑↓ reorder · 🗑 delete · `Ctrl+Z` undo · `Ctrl+N` new task · `Ctrl+L` log an update · `Esc` close |
| ⤷ right-click it | quick-add a task without opening the panel |
| `SUPER + SHIFT + T` | Open / close the tasks panel |
| Timer (bottom bar, centre) | **Focus timer** — click starts 25 min of focus (notifications muted), then a 5 min break (15 after every 4th). Click again pauses / resumes, middle-click stops |
| ⤷ right-click it | pick the task you're on (picking one while idle starts on it), +5 min, finish early, and the length: 25/5, 50/10 or 90/15. Finished sessions go into today's log in `~/notes/daily` |
| Weather (bottom bar, centre) | temperature + sky; hover for feels-like, humidity, wind, UV, rain in the next hours, sunrise/sunset and 4 days. Click refreshes, right-click changes the place |
| Tailscale icon (bottom bar, right) | how many of your machines are online; hover for each one's IP and link. Click: per machine **SSH in**, **Send files…** (Taildrop), **Copy IP**; connect / disconnect; exit node if you have one. Middle-click connects / disconnects |
| Spectrum next to the player | a small visualizer of what the speakers play, shown while a player on this laptop is playing |
| ⤷ the files | `~/notes/tasks.md` (open tasks) and `~/notes/daily/YYYY-MM-DD.md` (one per day). Check-ins pop up at 09:00 / 14:00 / 21:00; click one to open the panel |
| Wi-Fi icon (top bar) | Network panel — **Available** to scan/join/disconnect, **Saved** to connect, forget or edit stored ones |
| ⤷ right-click it | the old connection editor on its own |
| ⤷ in the panel | `F5` rescan · `Escape`/`q` close. Enterprise networks (eduroam etc.) open the editor — they need more than a password |
| `SUPER + I` | Settings (GNOME Settings) — also the cog in the top bar |
| `SUPER + X` | Lock screen |
| `SUPER + SHIFT + X` | Power menu — Lock / Suspend / Log out / Restart / Power off |
| ⤷ also | the power button, top-right of the bar. Press again or `Escape` to close |
| `SUPER + C` | Pick a colour → clipboard |
| `SUPER + ALT + C` | Accent colour for the whole desktop — previews live, Esc puts it back |
| ⤷ follows it | bar · sidebar · drawer · borders · lock · notifications · fuzzel · yazi · btop · tmux · starship · **VS Code chrome**. Syntax highlighting stays Catppuccin on purpose, in the editor and in `bat`/yazi |
| ⤷ when | bar/borders/notifications are instant; VS Code repaints live; yazi, btop and fuzzel repaint next time you open them |

Settings panels that do NOT work under Hyprland (they drive GNOME Shell/Mutter):
Displays, Appearance, Multitasking, Keyboard Shortcuts. Use `hyprctl monitors`,
`SUPER + W`, and hyprland.conf instead.

## Closing things

`SUPER + Q` closes *windows* only. These are layer-shell surfaces, not windows,
so it does nothing to them:

| Surface | Close with |
|---|---|
| Launcher (fuzzel) | `Escape` |
| Notifications (mako) | click it, or `makoctl dismiss --all` |
| Sidebar | `SUPER + A` |
| Lock screen | type your password |

## Windows

| Keys | Does |
|---|---|
| `SUPER + Q` | Close window (not Alt+F4) |
| `SUPER + T` | Theme picker — Catppuccin Mocha, Tokyo Night, Gruvbox Dark, Nord, Rosé Pine, Everforest, Dracula, Kanagawa; recolours the whole desktop (press again to close) |
| ⤷ in the picker | `←/→` or wheel move · `Enter` apply · `1`–`8` jump · `b` bar style: classic ⇄ floating islands · `Esc` close |
| Brightness pill (top bar) | scroll = brightness · click = 50 % · **right-click = night light** on/off · middle-click = warmer/cooler (4500 → 3500 → 2700 K) |
| `SUPER + Tab` | Workspace picker — the wallpaper carousel, one card per workspace with windows plus the next empty one, each a miniature of the workspace (press again to close) |
| ⤷ in the picker | `←/→` or wheel move (mouse wheel up / two-finger down = next) · `Enter` go there · `1`–`9` pick that workspace · `m` carry the focused window along (`Shift+Enter` = once) · `/` search window titles / apps · `Esc` close |
| `SUPER + H/J/K/L` | Move focus left/down/up/right (arrows work too) — also into / out of floating popups (screenshot save, tasks, notifications, …) |
| `SUPER + SHIFT + arrows` | Move the window |
| `SUPER + CTRL + arrows` | Resize the window |
| `SUPER + F` | Fullscreen |
| `SUPER + V` | Float this window |
| `SUPER + P` | Pseudotile — keep the slot, stop stretching to fill it |
| `SUPER + ALT + T` | Flip the split direction (was `SUPER + T`) |
| `SUPER + drag` | Left button moves, right button resizes |

## Workspaces

| Keys | Does |
|---|---|
| `SUPER + 1..0` | Go to workspace 1–10 |
| `SUPER + SHIFT + 1..0` | Send window to that workspace |
| `SUPER + scroll` | Cycle workspaces: occupied ones, then one empty, then back to 1 |
| `SUPER + SHIFT + scroll` | Transparency of the window under the mouse (70–100%) |
| ⤷ the OSD (top right) | shows the app's default as a mark on the bar; **Make NN% default** saves it for that app — new windows open at it, and its open windows still at the old default follow. Hover keeps the OSD up |
| `SUPER + SHIFT + middle-click` | Reset that window to its app's default (92%, Ghostty 100%, yazi 96% — list in `~/.config/hypr/opacity-defaults.conf`) |
| 3-finger swipe | Change workspace |
| `SUPER + S` | Toggle scratchpad (floating hidden workspace) |
| `SUPER + ALT + S` | Send window to scratchpad |

## Screenshots & clipboard

| Keys | Does |
|---|---|
| `SUPER + SHIFT + S` | Drag a region → clipboard + file |
| `Print` | Whole screen → clipboard + file |
| `SHIFT + Print` | Active window → clipboard + file |
| `SUPER + SHIFT + V` | Clipboard history (the top bar popup) |

Every capture is saved to `~/Pictures/Screenshots/` with a timestamp *and* put on
the clipboard; a notification confirms it. `Escape` cancels a region selection.

Top bar, left of centre:
- **Camera pill** — click: region screenshot · right-click: menu (screenshots,
  record screen / region / window, sound: desktop / mic / none, open OBS) ·
  middle-click: start recording. While recording it turns red with a timer;
  click to stop. If OBS is open, recording uses OBS (shows "OBS").
  Files: `~/Videos/Recordings/` (OBS: its own folder); "Open recordings
  folder" and the notification's "Show in folder" open yazi in grid view.
- **Clipboard pill** — history with image previews: type to filter, ↑↓, Enter
  copies, Del / right-click removes, "Clear all" (click twice).

Top bar, right: **mic pill** — click mutes, scroll sets the level, right-click
opens the mixer. Red while an app is using the mic; a camera / screen glyph
appears while a camera or the screen is being captured.

## Laptop keys (no SUPER needed)

Volume up/down/mute, mic mute, brightness up/down, media play/next/prev.
Brightness also: scroll on the lightbulb in the top bar; click it for 50%.
Closing the lid locks the screen.

## When things go wrong

| Keys | Does |
|---|---|
| `SUPER + SHIFT + E` | Quit to login screen — pick Ubuntu/GNOME there |
| `CTRL + ALT + F3` | Text console if the screen freezes (`F2` returns) |
| `hyprctl reload` | Re-read the config without logging out |

## Useful commands

| Command | Does |
|---|---|
| `~/.config/hypr/reload.sh` | Apply hyprland.conf edits (add `bar` to restart the bars + dock, `dock`, `mako`, `idle` or `all`) |
| `set-accent.sh <hex>` | Set the accent from a terminal · `--revert` restores the original theme |
| `set-accent.sh --resync` | **Run after editing any themed config** — see that script's header |
| `hyprctl reload` | Apply config edits instantly |
| `hyprctl clients` | List windows + their `class` (for window rules) |
| `hyprctl monitors` | Resolution, refresh rate, scale |
| `pgrep -a swaybg` | Check the wallpaper — swaybg has no IPC, the path is in its command line |
| `Hyprland --verify-config` | Check config for errors before logging out |

## The Windows drive won't mount

It is BitLocker, so it needs the passphrase. Store it once in your login
keyring and every mount after that is automatic:

```bash
secret-tool store --label='BitLocker Windows volume' \
    bitlocker-uuid <uuid>
```

Check it took: `secret-tool lookup bitlocker-uuid <uuid>`

Still asking? Run `~/.config/hypr/mount-windows.sh` in a terminal — that mode
prints why. A failure mentioning *hibernation* means Fast Startup is on in
Windows; turn it off rather than forcing the mount.

Config: `~/.config/hypr/hyprland.conf`
Bars + dock: `~/.config/quickshell/` (Quickshell — saving a file there reloads it live)
Lockscreen: `~/.config/hypr/hyprlock.conf`
