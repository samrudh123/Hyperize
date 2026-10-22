# Hyprland rice — setup guide + working notes

Two things in one file:

- **Part 1** sets this desktop up on an Ubuntu machine. The configs live in the
  Hyperize repo (this file included) and its `install.sh` does the work; Part 1
  says what it does and what you still adapt by hand.
- **Parts 2–4** are the hard-won details: landmines, how each piece works, and
  what to check after a change. Read Part 2 before changing anything.

Everything here was verified on a running system, not assumed. Where something
contradicts the upstream documentation, that is called out — several of these
cost hours to find.

> **Numbers in this file are examples, not facts about your machine.** Pixel
> geometry, output names, sizes and DPI were measured on the reference machine
> below. On anything else, re-measure with `hyprctl monitors` / `hyprctl layers`
> and re-derive window classes with `hyprctl clients` — do not copy them
> forward. The "Adapt per machine" table in Part 1 lists what always differs.

---

## The reference machine

What the measurements in Parts 2–4 were taken on — not a requirement:

| | |
|---|---|
| Hardware | a 14" laptop, single built-in panel |
| OS | Ubuntu 26.04 LTS |
| Display | **1920×1200 @ 60Hz**, scale 1 (output name: whatever `hyprctl monitors` says) |
| GPU | Intel (VA-API driver `iHD`) |
| Shell | zsh (login shell) |
| Sessions | `Hyprland` **and** GNOME both installed; GNOME is the fallback |

GNOME is deliberately left intact. `SUPER+SHIFT+E` exits Hyprland to the login
screen.

Note: GNOME reports a fractionally-scaled display at its *logical* size (e.g.
1680×1050 for a 1920×1200 panel at 114%). Use `hyprctl monitors`, not
fastfetch or GNOME Settings, for real geometry.

## Versions that matter

```
Hyprland 0.53.x      waybar 0.15.0       fuzzel 1.12.0
swaybg 1.2.1         mako                hyprlock / hypridle (Ubuntu builds)
nwg-dock-hyprland 0.4.11                 nwg-drawer 0.7.5
quickshell 0.3.2 (source → ~/.local/bin/qs)
```

Quickshell, both `nwg-*` tools, mpvpaper, the yazi file-picker portal and yazi
itself are **built from source / fetched into `~/.local`** — they are not
packaged for Ubuntu, and the nwg tools carry local patches this setup depends
on (`~/.config/hypr/patches/README.md`).

---

# Part 1 — Setting it up on a machine

```bash
git clone https://github.com/samrudh123/Hyperize ~/Hyperize
cd ~/Hyperize && ./install.sh
```

Then log out and pick **Hyprland** at the login screen. `install.sh` runs five
steps, each also runnable alone (`./install.sh packages|build|copy|system|wallpapers`):

| Step | Does |
|---|---|
| `packages` | `sudo apt install` everything in `packages/apt.txt` (desktop, tools, build deps) |
| `build` | JetBrainsMono Nerd Font, yazi, Quickshell, mpvpaper, the file-picker portal, nwg-drawer — into `~/.local` (~20 min; the Go/cgo build looks stuck for a while, it is not) |
| `copy` | copy every package's files into `~` (files of yours that differ go to `~/.dotfiles-backup/<date>/` first), seed the per-machine files in `extras/` — copies, not links: the repo and your configs stay independent |
| `system` | mask the systemd user units that fight the config (landmine 6), enable the aria2 and task-reminder units, make zsh the login shell |
| `wallpapers` | download the wallpapers listed in `wallpapers/sources.tsv` into `~/Pictures/wallpapers` |

## What the build step is (for doing it by hand)

- **nwg-drawer** (the `SUPER+D` app grid) is built from tag `v0.7.5` with
  `patches/nwg-drawer-0.7.5-context-menu.patch` — right-click → Open /
  favourites / Pin to sidebar. `build/nwg.sh` also builds the patched
  **nwg-dock-hyprland** with `WITH_NWG_DOCK=1`; that is only needed to go back
  to the pre-Quickshell dock. **The patches are not optional**: without them the
  build succeeds and silently falls back to upstream behaviour.
- **Quickshell** uses private Qt API: **rebuild it after every Qt update**
  (`build/quickshell.sh`) or it crashes on start.
- **Category filters for the drawer** live in `~/.local/share/nwg-data` (in the
  repo, `nwg` package). nwg-drawer's `dataDir()` walks `XDG_DATA_DIRS` for the
  first `<dir>/nwg-drawer/desktop-directories` and does **not** consult
  `XDG_DATA_HOME`; upstream's answer is `/usr/local/share/nwg-drawer`, which
  needs root. `app-grid.sh` prepends the user-owned dir instead. It **must** be
  a dedicated directory, not `~/.local/share` itself: `getAppDirs()` appends
  `~/.local/share/applications` unconditionally, so pointing at `~/.local/share`
  lists that dir twice and doubles every app in the grid.

## Adapt per machine

These are **wrong by construction** after a fresh install until you check them:

| What | Where | Why it differs |
|---|---|---|
| `LIBVA_DRIVER_NAME` | `hyprland.conf` env block | `iHD` is Intel; AMD (`radeonsi`) / NVIDIA need a different value or none |
| Monitor line | `hyprland.conf` | `,preferred,auto,1` is generic; add a scale for high-DPI panels |
| Bar/dock pixel geometry | Part 3 | measured on 1920×1200; re-measure with `hyprctl layers` |
| Pinned dock apps | `~/.cache/nwg-dock-pinned` | per machine: built from that machine's window classes, not carried over |
| Snap `.desktop` aliases | `~/.local/share/applications/` | only for snaps whose window class ≠ desktop file name; re-derive with `hyprctl clients` |
| Disk / trash dock entries | generated | `dock-places.sh` re-derives them from actual mounts |
| `python3` in keybinds | `hyprland.conf` | `/usr/bin/python3` on purpose — a project venv first on PATH would shadow it |
| Optional pieces | — | the dual-boot BitLocker volume (Part 3), OBS scenes: skip or configure if you use them |

**No home paths in configs.** Nothing in the repo contains `/home/<user>`:
scripts use `$HOME`, `.desktop` files wrap their command in `sh -c "… ~/…"`,
waybar/Hyprland `exec` strings use `~/` (they run through `sh -c`), btop names
its theme instead of pathing it, and the current-wallpaper state file
(`hypr/wallpaper`, an absolute path) is gitignored. Keep it that way — check
with `git grep -n "/home/"` before committing. The waybar fallback bars start
with `~/.config/waybar/fallback.sh` (it puts the now-playing plugin on
`LD_LIBRARY_PATH`, since waybar's `module_path` does no `~` expansion).

Per-machine values the repo deliberately does not carry: git identity
(`~/.gitconfig.local`), aria2's RPC secret (generated), OBS capture tokens,
API client IDs and device pairings.

## First login and verification

Expected on a healthy session:

- `hyprctl layers` shows the `qs-bar`, `qs-bottombar` and `wallpaper` namespaces
- exactly **one** `qs` process (`pgrep -x qs`)
- no `pid: -1` entries in `hyprctl layers`
- `Hyprland --verify-config -c ~/.config/hypr/hyprland.conf` prints `config ok`
- `systemctl --user is-active xdg-desktop-portal-hyprland` is `active` (screen
  sharing / OBS capture). If OBS records black after a log-out/in, the portal
  front-end outlived the session — `hyprland.conf` restarts it at login.

---

# Part 2 — Landmines

These are real, reproduced, and not in any documentation.

### 1. waybar's `image` module breaks the ENTIRE bar

Adding a single `image` module to a working config makes **every** module vanish.
No error in the log; the bar maps but renders nothing. Verified by injecting one
`image` into the known-good top bar config — the whole bar went blank.

**Never use `image` in waybar here.** Use `custom/*` with Nerd Font glyphs.

### 2. waybar cannot render a vertical bar

With `position: left` (or `right`), waybar builds the window and paints its
background, but **creates zero child widgets**. Its own debug tree shows:

```
window#waybar.background.left.<output>.NAME.mode-default:dir(ltr)
   (nothing)
```

A plain built-in `clock` does not appear either, so it is not about icons or CSS.
Horizontal bars build the full `box.vertical → modules-left/center/right` tree.

**A left/right dock is impossible in waybar 0.15.0.** That is the whole reason
the sidebar is `nwg-dock-hyprland` — it drives `gtk-layer-shell` directly and
shows real `.desktop` icons.

### 3. Hyprland 0.53 config syntax changed

| Old (everywhere online) | 0.53 |
|---|---|
| `windowrule = float, class:X` | `windowrule { name = …  match:class = …  float = yes }` |
| `windowrulev2 = …` | removed |
| `layerrule = blur, waybar` | `layerrule { name = …  match:namespace = …  blur = true }` |
| `gestures { workspace_swipe = true }` | `gesture = 3, horizontal, workspace` |
| `misc:new_window_takes_over_fullscreen` | removed |

In **both** rule blocks, `name` must be the **first** field, or you get
*"special category's first value must be the key"*.

**Always run `Hyprland --verify-config -c ~/.config/hypr/hyprland.conf`** before
telling the user to log out. It catches all of the above.

### 4. hyprpaper (0.8.3) is broken in Ubuntu

It connects to Wayland, gets the registry, then never parses its config (even with
explicit `-c`) and never creates a background layer. Every `hyprctl hyprpaper …`
verb returns *"Unknown hyprpaper request"*.

**We use `swaybg`.** `~/.config/hypr/hyprpaper.conf` is dead — left on disk only
so its absence isn't mistaken for a missing step.

### 5. brightnessctl cannot write the backlight

`/sys/class/backlight/intel_backlight/brightness` is `root:video 0664`. The user
was added to `video`, but **do not rely on it** — the working path is
systemd-logind's `SetBrightness`, which needs no group at all and is what GNOME
uses. Wrapper: `~/.config/hypr/brightness.sh`.

This silently broke three things at once (waybar scroll, the `Fn` keys, and
hypridle's dim step). If brightness misbehaves, check all three.

### 6. Ubuntu auto-enables systemd user units that fight the config

`hyprpaper`, `hypridle`, `mako` and `waybar` each ship a unit that is
`WantedBy=graphical-session.target` and gated only on `ConditionEnvironment=WAYLAND_DISPLAY`
— which **GNOME satisfies too**. They start under GNOME (and fail), and would
double-start under Hyprland alongside `exec-once`.

All four are **masked** (Part 1 step 6).

`disable` does **not** work — the symlinks live in `/etc/systemd/user/…wants/`
(global scope, root-owned) and systemd says so explicitly. Masking overrides it
from the user's own config. Hyprland's `exec-once` lines are the single source of
truth for what starts.

### 7. `pkill -f` is dangerous for signalling these daemons

`pkill -SIGUSR1 -f 'waybar.*dock.jsonc'` matches the **full command line of every
process**, including the shell running the pkill. SIGUSR1's default action is
*terminate*, so it kills unrelated processes. This killed several shells during
debugging, and later killed a shell mid-command with `pkill -f test-shot.py`.

Use `pgrep -x <name>` (matches the process *name*), or `ps -eo pid,args | grep -F`
and kill by pid. See `~/.config/hypr/dock-toggle.sh`.

Related: waybar 0.15.0 **does not** honour `SIGUSR1` to toggle visibility, despite
`on-sigusr1: toggle` being the documented default. Verified with `hyprctl layers` —
the layer never unmaps.

### 8. `gnome-control-center` refuses to run outside GNOME

Three separate blocks, all fixed in a user override at
`~/.local/share/applications/org.gnome.Settings.desktop`:

1. It exits unless `XDG_CURRENT_DESKTOP` names GNOME → `Exec=env XDG_CURRENT_DESKTOP=GNOME …`
2. `DBusActivatable=true` makes GIO activate it over D-Bus, **bypassing the Exec
   line entirely** (so the env override never applies; `gtk-launch` exits 0 and
   nothing happens) → set to `false`
3. `OnlyShowIn=GNOME;` hides it from launchers in other sessions → removed

Panels that **do not work** (they drive GNOME Shell/Mutter): Displays, Appearance,
Multitasking, Keyboard Shortcuts.

### 9. Process names are truncated to 15 characters

`nwg-dock-hyprland` has `comm` = **`nwg-dock-hyprla`**. `pkill -x nwg-dock-hyprland`
matches nothing and exits silently (the warning goes to stderr, easy to miss when
redirected). This left a stale instance holding its single-instance lock so new
ones would not start, and orphaned zombie processes whose Wayland surfaces stayed
registered in `hyprctl layers` as `pid: -1`.

Use the truncated name with `pgrep -x` / `pkill -x`. Do **not** switch to `-f`
(see landmine 7).

### 10. Orphaned layer surfaces break `grim`

After zombie `nwg-dock` processes left surfaces behind, `grim` began hanging and
then returning **all-black frames** — screencopy silently produces garbage rather
than failing. Hyprland itself stayed healthy (`hyprctl` responsive throughout).

If screenshots suddenly go black or hang, check for `pid: -1` entries:

```bash
hyprctl layers | grep "pid: -1"
```

They clear on the next login. `screenshot.sh` refuses to hand over an all-black
capture for this reason.

### 11. Restarting waybar alone makes it narrower

Layer-shell exclusive zones are resolved in **surface-creation order**. At login
`exec-once` starts waybar *before* `nwg-dock-hyprland`, so waybar claims the full
width and the dock's zone is carved out of what is left. Restart waybar on its
own and the dock's zone already exists, so waybar comes back shrunk —
`0 0 1920 40` becomes `~84 0 1836 40`, no longer reaching the left edge. (The
figures observed at the time were `8 5 1904 40` -> `91 5 1821 40`, when the bar
still had 8px side margins and a 5px top margin.)

Nothing is logged; waybar even prints its new width as if it were intended.

**`SIGUSR2` is not a way around this.** It does reload config and CSS in place,
and the process survives (same pid) — but it re-commits the layer surface, so the
bar shrinks exactly as a restart would. There is no in-place reload that keeps the
geometry.

This is a **waybar** problem only. `hyprctl reload` (for hyprland.conf changes —
keybinds, rules, env) leaves the bar untouched, so a config reload never needs
the restart dance.

**Restart both, waybar first:**

```bash
pkill -x waybar; pkill -x nwg-dock-hyprla     # 15-char comm, see landmine 9
hyprctl dispatch exec waybar                  # wait for it to map...
hyprctl dispatch exec "<the dock's full command line>"
```

`hyprctl layers | grep waybar` must then show `xywh: 0 0 1920 <height>` (it was
`8 5 1904 …` before the bar went flush). If x is ~91, the order was wrong.

### 12. Daemons started from a Claude Bash call die with VS Code

Anything launched from a tool call inherits the **VS Code snap's cgroup**
(`snap.code.code-*.scope`), because `setsid` / `start_new_session` changes the
session but **not** the cgroup. Compare:

```
mako, hypridle, swaybg   (exec-once)   -> session-NN.scope
waybar, nwg-dock         (relaunched)  -> snap.code.code-*.scope
```

VS Code grew to 12.4 GB once, the kernel OOM killer fired on that scope, and it
took the `workspace-stack.py` daemon with it — silently, with nothing in its own
log. A bar and dock relaunched that way are hostage to the editor.

**Start long-lived processes with `hyprctl dispatch exec`**, so Hyprland forks
them into the session scope exactly as `exec-once` does:

```bash
hyprctl dispatch exec waybar
hyprctl dispatch exec "/usr/bin/python3 ~/.config/hypr/workspace-stack.py"
```

This also removes the need to scrape `/proc/PID/environ` for a clean environment
(Part 3) — a Hyprland-spawned child inherits Hyprland's own env. Keep the
scraping trick only for one-shot GUI tools run directly from a tool call.

Verify: `cat /proc/$(pgrep -x waybar)/cgroup` must end in `session-NN.scope`.

### 13. Do NOT add GTK drag-and-drop to a layer-shell surface

Drag-to-reorder was first built with real GTK drag-and-drop and had to be
**reverted**: starting a drag froze the whole desktop, and the session had to be
logged out of to recover.

A Wayland drag is `wl_data_device.start_drag`, which puts the entire **seat**
into a drag grab — until the drag ends, every pointer event belongs to it and
nothing else responds. The dock is a layer-shell surface with no keyboard
interactivity, so `Escape` cannot reach it to cancel; the usual escape hatch does
not exist. Anything that stops the drop completing leaves a permanent, seat-wide
grab.

Nothing crashes, so **nothing appears in any log** — the dock keeps running and
the keyboard still works, which makes it look like a compositor hang rather than
an application bug. Recovery without logging out:

```bash
pkill -x nwg-dock-hyprla      # releases the grab; SUPER+A starts it again
```

**The working replacement** is the patch's `-reorder` flag — and it is
**confirmed working in normal use**: the pinned file was later found resequenced
by the user's own drags, with every entry intact. (I could never test the gesture
myself: no `ydotool`/`wtype`, and `/dev/uinput` needs root.) It tracks
`button-press` / `motion-notify` / `button-release` by hand and never calls
`start_drag`, so the only grab involved is the implicit pointer grab every button
click already takes, which the compositor always releases on button-up. If it
misbehaves, drop `-reorder` from the dock's arguments in `hyprland.conf` **and**
`dock-toggle.sh` and restart — no rebuild.

### 14. exec-once races: the dock can beat waybar to the exclusive zone

> **Defused, not deleted.** The dock no longer asks for an exclusive zone, so
> the failure below cannot happen in this form any more. `dock-start.sh` still
> waits for waybar, now for a cosmetic reason: a zone-less dock centres itself
> in the free strip, so mapping first means centring on the full 1200px and
> jumping 20px down when the bar takes its 40. The mechanism is kept on record
> because it applies to **any two** layer surfaces that both claim zones.

`exec-once` fires every line at roughly the same moment — Hyprland does **not**
wait for one child to map before starting the next. waybar is a GTK app with a
dozen modules and maps slower than nwg-dock, so the dock frequently commits its
layer surface first. Exclusive zones resolve in surface-creation order
(landmine 11), so the result at login was:

```
dock    6   6 78 1188     <- y=6, full SCREEN height, over the bar's strip
waybar 92   5 1820 40     <- pushed right and narrowed by the dock's zone
```

instead of `waybar 0 0 1920 40` / `dock 6 46 78 1148`. `-mt 6` is measured from
*inside* waybar's exclusive zone, so with no zone yet the dock lands at y=6 and
`-f` stretches it the whole screen.

Pressing `SUPER+A` appeared to fix it — hide/show re-commits the surface, and by
then waybar's zone exists. That is the tell: **if a layer surface is right after
a toggle but wrong at login, it is this race.**

Fixed by `dock-start.sh`, which waits for waybar before exec'ing the dock. The
wait checks for the waybar **process** *and* its layer, not the layer alone: a
killed waybar's surface lingers in `hyprctl layers` for a moment after the
process dies, and that ghost was enough to let the dock through early in
testing.

### 15. nwg-dock's `-c` gets no shell

It does `strings.Split(cmd, " ")` + `exec.Command(...)`, so a leading `~` is
never expanded and the launcher button silently does nothing. Use an absolute
path. Hyprland keybinds *do* go through `sh`, which is why the same string works
in a bind and not in `-c`.

### 16. Layer namespaces are not the program names — two blur rules were dead

**Two of the six `layerrule` blur rules matched nothing at all**, found while
adding the power menu:

- `blur-launcher` matched `^(fuzzel)$`, but fuzzel registers as **`launcher`**.
- `blur-dock` matched `^(dock)$`, but the sidebar registers as **`nwg-dock`**.

So the launcher and the sidebar were never blurred, for the life of the config.
Nothing warns you: a `layerrule` that matches no namespace is silently inert.
Found only because the new power menu looked transparent enough to read terminal
text through it, which prompted checking all of them.

**nwg-bar is worse:** it sets no namespace at all, so it inherits
gtk-layer-shell's library default and shows up as `gtk-layer-shell`. Its blur
rule has to match that generic name, which would also catch any other app that
leaves the namespace unset. Nothing else here does — nwg-dock, nwg-drawer,
waybar, fuzzel, mako and swaybg all set their own.

Same family of bug as the dead `#launcher-button` CSS in the dock: a selector
that names the program rather than what the program actually registers. When a
layer rule appears to do nothing, check the real namespace with `hyprctl layers`
while the surface is open, rather than assuming it matches the binary's name.

| program | namespace |
|---|---|
| waybar | `waybar` |
| nwg-dock-hyprland | `nwg-dock` |
| nwg-drawer | `nwg-drawer` |
| fuzzel | **`launcher`** |
| nwg-bar | **`gtk-layer-shell`** |
| mako | `notifications` |
| swaybg | `wallpaper` |

Audit every rule against reality rather than trusting the names — this is what
caught both dead ones:

```bash
python3 - <<'EOF'
import re, subprocess
conf = open(os.path.expanduser('~/.config/hypr/hyprland.conf')).read()
rules = re.findall(r'layerrule \{\s*name = (\S+).*?match:namespace = \^\((\S+?)\)\$', conf, re.S)
live = set(re.findall(r'namespace: ([\w-]+)',
    subprocess.run(["hyprctl","layers"],capture_output=True,text=True).stdout))
known = {"waybar","nwg-dock","wallpaper","launcher","nwg-drawer",
         "gtk-layer-shell","notifications"}
for name, ns in rules:
    ok = ns in live or ns in known
    print(f"{name:22} ^({ns})$ -> {'ok' if ok else 'MATCHES NOTHING'}")
EOF
```

Surfaces that only appear on demand (launcher, app grid, power bar,
notifications) will not be in `hyprctl layers` unless they are open, hence the
`known` set.

### 17. Literal Nerd Font glyphs do not survive being written by Claude

A shell script written with literal glyphs in it (`ICON_OFF=""`) came out with
**empty strings** — `od` showed just the two quote bytes. The power menu then
rendered as bare text with no icons, which looks exactly like a missing font and
sent me checking fontconfig and fuzzel's font setting first.

Write them as escapes instead, which are plain ASCII on disk:

```bash
ICON_OFF=$'\uf011'         # bash
```
```json
"format": "\uf011"         // waybar json — this one DID survive
```

And verify the codepoint exists before shipping it, rather than eyeballing a
render:

```python
from fontTools.ttLib import TTFont
f = TTFont("~/.local/share/fonts/JetBrainsMonoNerdFont-Regular.ttf")
cps = set().union(*(set(t.cmap) for t in f["cmap"].tables))
print(0xF011 in cps)
```

### 18. The zoxide warning in Claude's shells is not a misconfiguration

`zoxide: detected a possible configuration issue` appears on nearly every Claude
Bash call and **not** in the user's real shell. `.zshrc` runs
`zoxide init zsh --cmd cd`, which replaces `cd` and registers `__zoxide_hook` in
`chpwd_functions`. Claude Code's shell snapshot restores zoxide's *functions* but
not `chpwd_functions` (shell state, not a function), so the first `cd` in a
snapshot shell runs `__zoxide_doctor`, finds the hook missing, and prints advice
that does not apply.

```
real interactive zsh   chpwd_functions=__zoxide_hook   -> silent
Claude snapshot shell  chpwd_functions=<empty>         -> warns
```

Harmless. Silence it for Claude only with `"env": {"_ZO_DOCTOR": "0"}` in
`~/.claude/settings.json`; putting `_ZO_DOCTOR=0` in `~/.zshenv` would disable the
check everywhere, which loses a real diagnostic.

### 19. A translucent bar defeats colour-threshold measurement

Measuring the power button's position by classifying pixels gave contradictory
answers on every attempt. The cause is not the detector: `window#waybar` is
`alpha(@base, 0.80)`, so the bar is **see-through**. Where bright wallpaper sits
behind it the bar reads ~(47,46,59) — which is the button's own `surface0` fill
(45,44,60) to within two levels per channel. No threshold separates them, and the
same script gives different answers on different wallpapers.

Two ways out, both cheap:

- **Look at it.** `grim -g "1865,0 55x40"` then upscale 12x with NEAREST. At that
  zoom the rounded corners and the glyph are individually countable pixels.
- **Make it opaque first.** Temporarily set `background-color: #00ff00`, restart
  waybar, measure both bounding boxes exactly (pure green cannot be confused with
  a red glyph or any wallpaper), then restore the real colour. This is how the
  final 1875..1903 / 1885..1896 numbers were obtained, and it turned an hour of
  disagreeing estimates into one measurement.

The general rule, which has now cost time four separate times on this setup:
**a heuristic that measures the screen must be validated against a crop you have
actually looked at, before any conclusion is drawn from it.**

---

# Part 3 — How the pieces fit

## File map

```
~/.config/hypr/
  hyprland.conf        main config — verify with `Hyprland --verify-config -c`
  hyprlock.conf        lock screen
  hypridle.conf        idle: dim 150s → lock 330s → screen off 390s → suspend 1800s
  hyprpaper.conf       DEAD (hyprpaper broken) — swaybg is used instead
  brightness.sh        backlight via logind  {up|down|set|save|restore|get}
  dock-start.sh        starts the sidebar and OWNS its flags. Waits for waybar
                       to map first (landmine 14). Both exec-once and
                       dock-toggle.sh call it, so the flags live in one place.
  dock-toggle.sh       SUPER+A — toggles the dock; relaunches via dock-start.sh
  mount-watch.py       re-runs dock-places.sh when a volume mounts/unmounts, so
                       a BitLocker disk unlocked after login still gets an icon
  mount-windows.sh     unlock + mount the BitLocker Windows volume in user space
                       {--boot | --ensure | --open | no args}. SUPER+M opens it
                       in yazi; SUPER+E and yazi's `gw` also mount if needed.
  .windows-key         OPTIONAL fallback, user-created, mode 600: the BitLocker
                       passphrase in plaintext. Prefer the login keyring —
                       read the trade-off in the script header first.
  network-panel.py     the bar's Wi-Fi click target: Available (scan / join /
                       disconnect) + Saved (connect / forget / edit). GTK3,
                       app_id from set_prgname(), windowrules float + center it
  dock-places.sh       generates Trash + mounted-disk .desktop entries and pins them
  dock-icons.sh        applies dock-icons.conf (custom sidebar icons)
  dock-icons.conf      "<pinned entry> = <icon name or path>", one per line
  dock-pin.sh          {status|add|remove} <desktop-id> — maps a .desktop ID to a
                       window class and pins it in the SIDEBAR; called by the
                       patched nwg-drawer's context menu
  app-grid.sh          SUPER+D and the top bar's launcher button -> nwg-drawer
  yazi-terminal.sh     yazi <C-t> — a terminal at the hovered directory
  screenshot.sh        SUPER+SHIFT+S / Print / SHIFT+Print {region|screen|window}
  workspace-stack.py   daemon: keeps workspaces gap-free. `--once` compacts by
                       hand; HYPR_STACK_DEBUG=1 to trace
  wallpaper-grid.py    SUPER+W — grid of wallpaper THUMBNAILS. `--lock`
                       (SUPER+SHIFT+W) is the same grid for the LOCK SCREEN,
                       with an extra `screenshot` tile. Delegates the actual
                       setting to set-wallpaper.sh / set-lockscreen.sh.
  set-wallpaper.sh     DESKTOP wallpaper (swaybg)
                       {--restore | <path> | no args = fuzzel name-only picker,
                       kept as the fallback}
  set-lockscreen.sh    LOCK SCREEN image (hyprlock), deliberately SEPARATE from
                       the desktop. hyprlock has NO --verify-config, so a typo is
                       only found when the screen locks — this script backs the
                       file up, checks braces stay balanced, and restores on
                       failure. Edit via the script, not by hand.
                       {--screenshot | --show | <path> | no args = fuzzel
                       name-only picker, kept as the fallback}
  wallpaper            plain-text path of the current wallpaper
  power-menu.sh        the top bar's power button -> fuzzel menu:
                       Lock / Suspend / Log out / Restart / Power off
  reload.sh            apply config edits without logging out
                       {hypr|bar|dock|mako|idle|all} — encodes the waybar-first
                       restart order (landmine 11) so it cannot be got wrong
  postlogin-check.sh   run after a fresh login: prints the bar/dock geometry and
                       says whether the exec-once race (landmine 14) was won.
                       It HARDCODES the expected geometry — update it whenever
                       the bar's margins change, or it cries wolf.
  patches/             local source patches + rebuild recipe (README there)
  CHEATSHEET.md        user-facing keybinds (SUPER+/ opens it)

~/.config/waybar/          config.jsonc + style.css    (top bar)
                           dock.jsonc/dock.css — UNUSED, the old bottom dock
~/.config/nwg-dock-hyprland/style.css     sidebar styling
~/.config/nwg-drawer/drawer.css           app grid styling
~/.config/nwg-bar/         bar.json + style.css — the power dialog

~/.local/bin/              nwg-dock-hyprland, nwg-drawer (patched builds),
                           yazi, zellij   — NOT on Hyprland's PATH
~/.local/share/applications/
                           code.desktop, brave.desktop   snap class aliases
                           org.gnome.Settings.desktop    GNOME Settings fix
                           dock-*.desktop                generated places
~/.cache/nwg-dock-pinned   sidebar pins — bare WINDOW CLASSES, one per line
~/.cache/nwg-pin-cache     the drawer's own favourites row — .desktop IDs
~/Pictures/wallpapers/     wallpapers (SUPER+W to pick)
~/.cache/wallpaper-thumbs/ generated thumbnails, keyed <name>.<mtime>.png
```

Online keybind reference: https://claude.ai/artifact/QtvkUqWFVMf9392AwsNaea

## Look and feel

- **Catppuccin Mocha everywhere.** `base #1e1e2e`, `text #cdd6f4`, `mauve #cba6f7`
  (accent), `surface0 #313244`, `surface1 #45475a`, `crust #11111b`,
  `red #f38ba8`, `green #a6e3a1`.
- Font: **JetBrainsMono Nerd Font**.
- Gaps are small (3/6px) and blur is modest (`size 4, passes 2`) — a 14" laptop
  on battery. `vfr = true` matters.

## The shell (Quickshell, since 2026-10-09)

One process, `~/.local/bin/qs` (exec-once), config in `~/.config/quickshell/`:

| File | What |
|---|---|
| `shell.qml` | entry point: `TopBar`, `BottomBar`, `Dock`, `OpacityOsd`, `WallpaperTransition`, `WorkspacePicker`, `WallpaperPicker` |
| `Theme.qml` | Mocha colours, the live accent (`hypr/theme/accent`, watched — set-accent.sh needs no template for it), `exec()` via `hyprctl dispatch exec`, Pango→StyledText |
| `Pill.qml` / `ScriptPill.qml` | the 32px module pill; ScriptPill runs an existing waybar JSON script (polled or long-running) |
| `TopBar.qml` | one per screen since 2026-10-21 (shell.qml `Variants` over `Quickshell.screens`, same for `BottomBar.qml`; a duplicated screen has no wl_output so gets none). Shared state in the `BarState.qml` singleton (bottom bar shown, keep-awake; `primary` = laptop panel, runs the focus timer's `next`; `active` = focused monitor's bars own the IPC targets, `IpcHandler.enabled`). Namespace `qs-bar`, full width × 40 (42 in the islands style). Left: launcher · workspaces with per-workspace app icons · screenshot/record (`RecordPill.qml`) · clipboard (`ClipboardPopup.qml`) · submap, then cpu/mem/temp. Centre: window state badge + title. Right: tray, audio (PipeWire), mic + privacy light (`MicPill.qml`), backlight, displays (`DisplayPill.qml`, only with 2+ monitors: duplicate/extend via `hypr/display-mode.py` = runtime `hyprctl keyword monitor` rules, unknown monitors DUPLICATED by default (`DEFAULT` in the script), choices remembered per monitor description in `~/.local/state/display/layouts.json`, re-applied by `sync` on monitoradded/removed + configreloaded since a reload drops runtime rules; `qs ipc call display toggle\|cycle\|menu\|set …`; SUPER+P = `cycle`, toggle + OSD; pseudotile moved to SUPER+ALT+P; state/script runs in the `Displays.qml` singleton), network (NetworkManager), battery (UPower), clock + calendar card, bell, settings, power |
| `BottomBar.qml` / `NowPlaying.qml` | namespace `qs-bottombar`; the downloads pill (dl-popup) sits at the start of its right group. The two player pills run `now-playing.py --cffi --scope local\|remote` with the exact argv the CFFI plugin used, so `nudge_bars()`'s pkill pattern still matches; seek zone/drag/scroll as in `nowplaying.c` |
| `FocusPill.qml`, `Visualizer.qml`, `TailscalePill.qml` | bottom bar, 2026-10-12. Centre island (pushed aside / hidden when the sides leave no room): focus timer (`hypr/focus.py`, state `~/.local/state/focus/state.json` watched — the pill counts down itself and calls `focus.py next` at zero; DND during work, sessions logged via `tasks.py log`) + weather (`hypr/weather.py`, Open-Meteo, place in gitignored `hypr/weather-location`, cache 15 min). Visualizer beside the laptop player while it plays: `hypr/visualizer.py` = `pw-record` on the sink monitor + numpy FFT (OPENBLAS_NUM_THREADS=1 or numpy's import alone burns 1.7 s CPU). Tailscale pill polls `tailscale status --json` (user is operator: up/down without sudo); SSH / Taildrop (`hypr/tailscale-send.sh`, files picked with `hypr/pick-files.sh` = yazi `--chooser-file`). `qs ipc call bottombar menu focus\|tailscale\|…` opens a pill's menu |
| `Dock.qml` / `DockButton.qml` | namespace `qs-dock`, x 6 w 54. Same pinned file and Mocha icons as nwg-dock; drag a pin to reorder, right-click menu (windows / new / pin / close) |
| `Tray.qml`, `MenuPopup.qml`, `MenuRow.qml`, `Tooltip.qml`, `Clock.qml`, `Battery.qml`, `Workspaces.qml`, `Stats.qml` | the rest; Stats reads /proc and /sys directly |

- Saving any file there **hot-reloads** the shell. `reload.sh bar` = real restart.
- Wallpaper changes are animated by `WallpaperTransition.qml` (bottom-layer
  overlay over swaybg/mpvpaper; effects in `shaders/transition.frag`, compile
  with `/usr/lib/qt6/bin/qsb --qt6 -o transition.frag.qsb transition.frag`).
  set-wallpaper.sh drives it (`qs ipc call wallpaper transition|ready`); kind in
  `~/.config/hypr/wallpaper-transition`, chosen in the picker with `t`.
  set-accent.sh no longer runs `reload.sh bar` (the shell follows the accent
  live; a restart also killed a running transition).
- THEMES (2026-10-11) — SUPER+SHIFT+T (SUPER+T until 2026-10-17) `ThemePicker.qml` (+ `ThemePreview.qml`, a
  palette-drawn mini desktop per card) → `hypr/set-theme.sh <id>`. Palettes in
  `hypr/rice-theme.py`: 8 themes, each a map of Catppuccin Mocha's 26 roles.
  Templates stay MOCHA; `subst` recolours Mocha hex (any case, also the first
  6 of rgba 8-digit), `r, g, b` triplets and (--ints) LibreOffice longs.
  set-accent.sh render = subst (cached theme/rendered/<id>/) then accent
  token; at Mocha it's the identity (verified: Tokyo Night → Mocha round trip
  byte-identical for all 33 themed files). Accent keeps its ROLE across
  themes (map-accent). theme/name + theme/palette.json (Theme.qml reads it
  live: `Theme.pal`, `themeId`). app-accent.sh: GTK3 = recoloured copy of
  catppuccin-mocha-<role> as ~/.local/share/themes/rice-<id>-<role>-…;
  Discord inlines the fetched Catppuccin CSS recoloured (cache
  theme/discord/); Spotify color.ini / YTM css re-rendered from
  theme/pristine/; kde-theme.sh & libreoffice-theme.sh subst their output;
  VS Code via catppuccin.colorOverrides (identity block in the template).
  GTK python panels call `_rice_subst(CSS)`; accent-picker offers the theme's
  accents; dock icons regenerated (RICE_PALETTE) + `?<themeId>` URL bust.
  Ghostty config is now in the manifest; set-theme sends SIGUSR2 (reload).
  Backups *.pre-themes. eff1f5 (Latte base) is mapped ONLY in GTK themes —
  spicetify's color.ini holds all four flavours.
- Bar style (2026-10-11): theme/bar-style `classic|islands` (`b` in the theme
  picker), `Theme.islands`; `Island.qml` wraps module groups (classic: plain
  Row). Islands: bars 46 px, groups float as rounded glass.
- Night light (2026-10-11): `hypr/night-light.sh` (right/middle-click the
  brightness pill) = Hyprland screen_shader generated per kelvin in
  ~/.cache/night-light (GLSL 300 es, tex300.vert), state theme-independent in
  hypr/night-light + night-light.conf which hyprland.conf SOURCES (survives
  reloads/logins). No package needed.
- `WallpaperPicker.qml` (2026-10-10) — SUPER+W / SUPER+SHIFT+W
  (`qs ipc call wallpicker toggle desktop|lock`, also `open|close|status`).
  wallpaper-picker.py rebuilt in the shell: same carousel / filters / keys /
  transitions strip / accent sync, opens in ~30 ms instead of ~400 ms. The
  list comes from `hypr/wallpaper-index.py desktop|lock --card WxH` (GTK-free,
  ~40 ms: colour buckets via the old classify() + colours.json, cached card
  PNGs; missing cards/posters are made by a detached child AFTER printing).
  The last list per mode is shown at once and only re-rendered if it changed.
  Cards load only within ±12 of the selection. Lock mode's Live screen card
  = ScreencopyView of the screen captured before the picker maps (220 ms
  wait when swapping from the desktop picker) + MultiEffect blur. Layer rule
  `noanim-qs-pickers` drops Hyprland's layersIn fade for both pickers (they
  fade themselves). wallpaper-picker.py still works standalone. Backups
  *.pre-qswallpicker.
- `WorkspacePicker.qml` — SUPER+Tab (`qs ipc call wspicker toggle`, also
  `open|close|status`). wallpaper-picker.py's carousel rebuilt in QML; the
  slanted card (clip, shadow, outline) is `shaders/card.frag`. Stops = the
  workspace-scroll.sh set (occupied + 1 + the next empty + current). Window
  stills come from hyprland-toplevel-export (ScreencopyView), BUT Hyprland
  renders an export with the workspace's alpha, and the `fade` workspace
  animation leaves hidden workspaces at alpha 0 → blank frames. So a hidden
  cache of ScreencopyViews (one per toplevel) captures windows only while
  their workspace is on screen (450 ms after workspace/focus/title/move
  events, every 5 s, and on open) and the cards sample the last good frame.
  After a qs restart, windows on workspaces not yet revisited show their app
  icon instead. togglesplit moved to SUPER+ALT+T. Wheel up = next card (both
  pickers, flipped 2026-10-10).
- A global Shift+wheel flip (Shift binds toggling input:scroll_factor) was
  tried 2026-10-10 and REVERTED — it reversed scrolling in every app. Note:
  a negative scroll_factor also hangs Hyprland 0.53 unless
  emulate_discrete_scroll = 0.
- Window borders (2026-10-10): 3px bevel gradient (accent ff→cc→33, 135deg)
  + accent shadow (range 12, offset 3 2, `rgba(<accent>77)`) = lifted 3D
  look. Both are templated (@@ACCENT@@) and set live in set-accent.sh
  reload_live(). Backups *.pre-wspicker, set-accent.sh.pre-shadow (archived in ~/.dotfiles-backup/pre-backups-2026-10-17.tar.gz).
- IPC: `qs ipc call dock toggle|open|close` (SUPER+A via dock-toggle.sh),
  `qs ipc call bottombar …` (bottom-bar.sh). `qs log` for errors.
- Rebuild after any Ubuntu Qt update (private Qt API):
  `cd ~/.local/src/quickshell && git pull && cmake --build build && cmake --install build`
  (configured with `-DCRASH_HANDLER=OFF`: cpptrace is not packaged).

Quickshell landmines found while building it:

- An IpcHandler function named **`show`** is unreachable: `qs ipc call dock show`
  parses `show` as the `ipc show` subcommand. Use open/close.
- QML FINAL members cannot be redeclared: a `focus()` function, a `closed`
  signal on a PopupWindow, a `data` property on an Item all fail or are ignored
  (the load error points at the line).
- `grim` hangs (never returns) while the screen is DPMS-off — check
  `hyprctl monitors | grep dpms` before blaming the shell.
- One hot reload crashed the process (no crash handler, so no trace). If the
  bars vanish, `reload.sh bar`.

## The top bar (waybar) — previous setup

**40px** tall, **flush to the top and both edges** — all three margins 0, so the
surface is `0 0 1920 40`.

**The background belongs on `window#waybar`, not on the module groups.** This is
the trap: the bar used to carry `window#waybar { background: transparent }` with
each of `.modules-left/center/right` painted as its own rounded slab. Widening
the surface to the full display then changed the geometry and **nothing
visible** — what you see is the slabs, and they are sized by their contents, so
the bar still read as three floating pills with wallpaper between them. Moving
the background to the window and making the groups transparent is what makes it
one continuous panel, the way the sidebar is one panel top to bottom.

`border-radius: 0` on the window, since it touches both screen edges — rounded
corners get clipped by the bezel and look like a mistake. Same reason
`margin-top` is 0: a square full-width bar floating 5px down leaves a wallpaper
strip above it.

**`margin-top` feeds the dock.** The bar's exclusive zone is the only thing
reserved on this screen, and the sidebar — which reserves nothing — centres
itself in what is left. Zone 40 puts a 900px dock at y=170; change the bar's
margin and the dock moves, with no dock edit.

Right-hand modules use `padding: 0 9px` (`#tray` 8px). They were briefly 14px/12px;
at that width the eight status readouts read as scattered rather than as one group,
so they came back down. Below ~8px the coloured glyphs start touching their
neighbour's digits.

`custom/logo` is **not** in `modules-left`: its format was two literal space
characters (the glyph had gone missing), so it rendered ~50px of invisible,
clickable padding left of workspace 1. Removing it moved the active pill from
x=64 to x=18. The definition is kept in the config, unused.

`custom/power` at the far right runs **`nwg-bar`** (apt, 0.1.6) — a centred
dialog with Lock / Suspend / Log out / Restart / Power off, styled Catppuccin in
`~/.config/nwg-bar/style.css`. `power-menu.sh` is the fuzzel fallback that
preceded it and still works: swap the module's `on-click` back to it, nothing
else changes.

Three things about nwg-bar worth knowing:

- **Its shipped `bar.json` is sway-specific** — `swaylock -f -c 000000` and
  `swaymsg exit`, neither of which exists here. The local copy uses `hyprlock`
  and `hyprctl dispatch exit`.
- Shutdown is plain `systemctl poweroff`, not the shipped `systemctl -i
  poweroff`. `-i` ignores inhibitors, which would let it power off through
  something that asked not to be interrupted.
- **`-f` does nothing for a centred bar.** It stretches an *edge*-positioned one,
  so with the default centre position the window stays content-sized (622x148
  here) and there is no full-screen scrim to dim the desktop. The `window`
  background in its CSS therefore only tints the panel itself.
- **It is self-toggling.** Launching nwg-bar while one is already running
  terminates the running instance instead of stacking a second dialog — verified
  over four alternating launches, process count and layer-surface count going
  1,0,1,0 with nothing left behind. That is why `SUPER + SHIFT + X`
  (`bind = $mainMod SHIFT, X, exec, nwg-bar`) needs no toggle wrapper and why
  holding the key cannot pile up dialogs. It does **not** close on focus loss.

Being the **last** module on a bar that touches the screen edge, it carries
`margin: 4px 2px 4px 6px`. Its clearance from the bezel is that 2px **plus**
`.modules-right`'s own `padding: 0 6px` = 8px, measured: the button occupies
1883..1911 and all four rounded corners are intact. It gets a subtle `surface0`
fill rather than a filled pill so it reads as a button without competing with
the mauve clock.

**An earlier version of this file said `margin-right: 2px` clips the corners and
that only the module's own margin separates it from the edge. That is wrong** —
setting exactly 2px now leaves the corners clean. The claim dates from when
`.modules-*` still painted their own background slabs; what was measured as "the
button's fill running to x=1919" was almost certainly the **group slab** behind
it, not the button. Once the background moved to `window#waybar` and the groups
became transparent, the group's right padding was visible as real clearance.
Both sides of the bar do honour the group padding.

Between them, those two claims cost four bad measurements — a baseline pixel
sampled on the clock pill, a detector that counted glyphs as fill, one that
reported 0px clearance for a button visibly clear of the edge, and this one,
which measured a slab and called it a button. **Crop the last 80px and look at
it at 12x**; a clipped corner is unmistakable and no threshold is involved.

Its horizontal padding is **asymmetric on purpose**: `padding: 0 12px 0 8px`.
The power glyph U+F011 has an uneven side bearing — its ink overflows its advance
box to the right — so a symmetric `0 10px` put it 3px off-centre (left gap 10,
right gap 7) inside a 29px-wide button. 12/8 keeps the same 20px total width, so
the button does not change size, and pulls the ink back to 8/9. That residual 1px
is arithmetic, not a bug: a 12px glyph in a 29px button leaves 17px to split, and
17 is odd. Same vertically — a 13px glyph in a 32px box splits 9/10. Do not chase
those last pixels; they cannot be removed, only moved from one side to the other.

logind+polkit grant power-off/reboot/suspend to
the active session with no authentication (check with `pkcheck --action-id
org.freedesktop.login1.power-off --process $$`), so none of it needs sudo.
Hibernate is left out on purpose: polkit does not grant it, and swap is smaller
than RAM. Log out / Restart / Power off ask a second time, Cancel first.

Workspace buttons style only `.active` and `.urgent` — an occupied workspace looks
identical to an empty one. Fine here because the workspace stacker keeps them
contiguous, but worth knowing.

## The sidebar (nwg-dock, patched)

```
-p left -i 60 -r -ml 6 -l top -c /home/<user>/.config/hypr/app-grid.sh
-lp end -bottom dock-disk-,dock-trash -reorder
```

Surface on this machine: **`6 170 78 900`** — a content-sized pill, floating,
vertically centred in the strip the bar leaves free.

- **No `-x`, so no exclusive zone.** The dock draws *over* the tiling layout
  instead of reserving the left edge: `hyprctl monitors` reports
  `reserved: 0 40 0 0`, and windows run full-width underneath it. Toggling it
  with `SUPER+A` no longer reflows every window on the workspace.
- **No `-f`.** The surface is only as tall as its icons. Without `-f` it is not
  anchored top or bottom, and gtk-layer-shell centres an unanchored axis — so
  "centred" needs no flag. `-a` only has meaning with `-f` and is therefore
  gone, as are `-mt`/`-mb`: layer-shell margins apply only on anchored edges.
- **`-l top` is now explicit.** `-x` used to force the layer; with it gone,
  nwg-dock's default is `overlay`, which would put the dock above the app grid,
  the power menu and notifications. `top` keeps it where it has always
  rendered, alongside waybar.
- **Height follows the pin count** — and disks come and go with mounts, so do
  not hardcode it anywhere. `postlogin-check.sh` asserts x/width, "not full
  height" and "centred ±4px" instead.
- The dock still *moves* with the bar: with no zone of its own it centres in
  whatever the bar does not reserve, so `y = 40 + (1160 - height)/2`.
- `-r` keeps it resident so `SUPER+A` toggles via `SIGRTMIN+1` instead of
  restarting the process.
- `-lp end` + the patch pins the "more apps" launcher to the **bottom**.
- `-bottom dock-disk-,dock-trash` packs those pins with the launcher into
  `#bottom-box` at the foot, so Trash and disks sit directly above the grid, and
  the separator line lives on that box so it spans the whole group. Matching is
  by **prefix, not file position** — a bottom pin moved up the pinned file stays
  in the group, it only changes order within it.
- The separator's distance from the icon below it is `#bottom-box`'s
  `padding-top`. The row is anchored to the bottom, so shrinking that padding
  moves the *line down* toward the icons rather than moving the icons up.
- **Icon size vs sidebar width — the one non-obvious knob.** The dock is sized by
  its *content*, so raising `-i` alone just widens the whole bar and the icons
  look no bigger relative to it. Three CSS values are the counterweight, all in
  the dock's style.css:
  - `button { padding }` — space around each icon: cut it and the bar narrows
    while the icon grows, both at once
  - `button { margin }` — the **vertical** gap between icons; this is what reads
    as "compact"
  - `#box { padding }` — dead space down both edges of the whole strip

  The progression here, each step measured with `grim` + the widest contiguous
  run of icon pixels:

  | `-i` | button padding / margin | `#box` padding | surface | drawn icon |
  |---|---|---|---|---|
  | 44 | 9px / 5px | 14px 8px | 83px | 33px (40%) |
  | 52 | 6px / 5px | 14px 8px | 83px | 39px (47%) |
  | 60 | 3px / 3px | 12px 5px | **78px** | **45px (58%)** |

  So bigger icons and a *narrower* bar are not in tension — the padding pays for
  both.

**The flags live in `dock-start.sh` only** — `exec-once` and `dock-toggle.sh`
both call it, so there is nothing to keep in sync any more. That script also
waits for waybar before mapping (landmine 14).

### Pins are window classes, not .desktop IDs

`~/.cache/nwg-dock-pinned` holds **bare window classes**. Getting this wrong is
subtle and looks like a missing feature: the dock draws a pin as a plain icon
when `inTasks(pin)` is false and as a *task button* (running dot, `#active`
highlight) when true — and `inTasks` compares against the window `Class`. With a
`.desktop` suffix nothing matches, so the app renders once as a dotless pin **and
again** as a running task. It merges fine given the right format. Do not paper
over it with `-g`, which only hides the running entry and loses the dot.

Get a class with `hyprctl clients | grep class`.

**Never take the class from `StartupWMClass=`.** That is the X11 `WM_CLASS`;
Hyprland reports the Wayland `app_id`, and they differ — `brave_brave.desktop`
says `StartupWMClass=brave-browser` while Hyprland reports **`brave`**.
`hyprctl clients` is the only source of truth.

Icon lookup resolves `<entry>.desktop`, then falls back to a fuzzy filename
search. Snaps break this when class ≠ filename (class `code` vs
`code_code.desktop` → orange `icon-missing.svg`). Fixed with aliases at
`~/.local/share/applications/{code,brave}.desktop`, `NoDisplay=true` so they stay
out of app lists while nwg-dock still reads them. Any snap with a mismatched
class needs the same treatment.

### Three separate levers for customising it

- *Which icons, interactively:* the dock has right-click menus. Right-click a
  pinned icon → **Unpin**; right-click a running app → **Pin**, writing the bare
  class, so this route never hits the duplicate bug.
- *Order:* the line order of `~/.cache/nwg-dock-pinned`, or drag an icon onto
  another (`-reorder`). Bottom-group pins and the launcher are excluded from
  dragging.
- *Which image an entry draws:* `dock-icons.conf` + `dock-icons.sh`. The dock
  draws whatever the resolved `<entry>.desktop` has in `Icon=`, so the script
  writes an override into `~/.local/share/applications` (which outranks
  `/usr/share/applications`) with a custom `Icon=` and an `X-Dock-Icon=managed`
  marker; dropping the conf line makes the next run delete the override. Being
  the standard XDG mechanism, the icon also changes in the app grid — dock-only
  icons are not possible this way. For generated places it edits `Icon=` in place
  instead, so run `dock-icons.sh` **after** `dock-places.sh`.

### Live updates

The patched dock re-reads `~/.cache/nwg-dock-pinned` the moment it changes.
Upstream does **not**: `buildMainBox()` does re-read the file, but it is only
called from `refreshMainBox(true)`, whose only caller is the `activewindowv2`
branch of the socket2 loop, guarded on the window address differing. So upstream,
an edit shows up only when you next focus a *different window* — which is why
"Unpin from sidebar" looked broken. `SIGRTMIN+2` does not help; `WindowShow` only
calls `win.ShowAll()`.

Do not measure this by the dock's surface **width** — it drifts on its own as GTK
re-measures, and reading it as signal once led to the wrong conclusion twice.
Screenshot the icons instead.

### The one icon that would not unpin

Separate from the above, and it outlived it: with the fsnotify patch in place
"Unpin from sidebar" still did nothing for **JDownloader**, and only JDownloader.

`dock-pin.sh` turns the drawer's `.desktop` ID into the dock's bare window class.
For this app all three available identifiers are *different strings*:

| Source | Value |
|---|---|
| desktop file stem | `install4j_1nco9fl-JDownloader2` |
| `StartupWMClass` | `install4j-org-jdownloader-update-launcher-JDLauncher` |
| the pinned line | `JDownloader` |

With the app closed, resolution fell through to the stem, which matches no line
in `~/.cache/nwg-dock-pinned`. So `status` answered `unpinned` for an app plainly
*on* the sidebar — the drawer offered "Pin", and "Unpin" grepped out a line that
was never there. The icon stayed, silently, forever.

Every other entry resolves because the stem already equals the pinned line
(`dev.local.btop`, `org.gnome.Nautilus`, …) or because `X-SnapInstanceName`
supplies it (`discord_discord` → `discord`). Tested all fourteen: **one** failed.

The fix is a new step 4 — before guessing, ask whether the pinned list already
has a line naming this app, comparing the stem, `StartupWMClass`,
`X-SnapInstanceName`, the `Name` with spaces stripped, and the `Name`'s first
word (which is what catches `JDownloader` from `Name=JDownloader 2`). It only
ever reuses an existing line, and only on a *unique* match, so it cannot invent
an entry or unpin the wrong icon — worst case it declines and behaves as before.

Verified by round trip against the live dock, not just by reading `status`:
unpin → the icon disappears; re-pin → it comes back. Worth knowing that the
re-pin writes the **stem**, `install4j_1nco9fl-JDownloader2`, because once the
line is gone there is nothing left to match — and that entry renders the icon
perfectly well, since nwg-dock also resolves a pinned name against desktop file
basenames. It lands at the *end* of the list, as any unpin/re-pin does; order is
just line order, so drag it back or edit the file.

The true Wayland class is still unconfirmed — it needs JDownloader actually
running, and launching a download manager to find out was not worth the side
effects. It does not matter for pinning, only for whether a running JDownloader
would draw a second, separate task icon.

### Trash and disks are faked

nwg-dock knows nothing about volumes or trash. `dock-places.sh` writes
`dock-trash.desktop` and one `dock-disk-<label>.desktop` per mount under
`/run/media/$USER`, `/media/$USER` or `/mnt`, then appends their names to the
pinned list. A pin matching no window class is drawn as a plain icon that
launches its `Exec` — exactly what a place needs. Both open in `nautilus` (yazi
cannot do `trash:///`). The script preserves app pins the user added by hand and
only rewrites its own entries.

`mount-watch.py` re-runs the script whenever the mount table changes, so this is
now a live view. It matters more than it sounds: the Windows partition here is
**BitLocker**, so it is locked at login and only mounts once you unlock it in
Files — i.e. *always* after `exec-once` has already run. Without the watcher its
icon could never appear on its own, which is exactly how it behaved.

The watcher polls nothing: `/proc/self/mounts` is marked `POLLPRI` by the kernel
when the mount table changes, so `poll()` blocks at zero cost until something
actually mounts. It debounces 1s (mounting rewrites the table several times),
compares only the paths that would become dock entries, then re-runs
`dock-places.sh` and `dock-icons.sh`. The dock's own fsnotify watcher does the
rest, so the icon appears with no restart. Verified end to end with a loopback
volume: mount → icon appears, unmount → icon goes.

### Duplicate icons: a pin plus a live task, for the same app

Separate bug, same root cause family. A pinned line is a **window class**; when
the class the app actually reports differs, the dock cannot match the running
window to the pin, so it draws both — a dead pin and a second live task icon,
often with a generic icon. This is the Brave bug from session one, recurring.

All twelve app pins were launched and their real class read from
`hyprctl clients`. **Three** were wrong:

| App | Pin said | Actually reports | Fix |
|---|---|---|---|
| Firefox | `firefox` | `firefox_firefox` | pin renamed |
| DBeaver | `dbeaver-ce` | `DBeaver` | pin renamed |
| OpenShot | `org.openshot.OpenShot` | `python3` (!) | desktop override, below |

The other nine match and were left alone. Note `X-SnapInstanceName` is **not**
reliable as a class: it works for brave/code/discord but the firefox snap
reports `firefox_firefox`, which is what broke that one.

Two traps when measuring this:

- **Read the class late.** DBeaver is Java/SWT and shows `Java` on its splash,
  then `DBeaver` on the real window, then `Dbeaver` on the launcher. Sampling
  1.5s after the window maps recorded `Java` — a class that is both wrong and
  generic. Wait for the app to finish loading, and list *all* its windows.
- **Trust the screenshot, not the class string.** The duplicate is visible: the
  pin sits inert while a second icon appears below the pinned group carrying the
  running dots.

#### OpenShot needs a desktop override

Its Wayland app_id is literally `python3`, which is unusable as a pin: generic
(any other Python GUI app would merge into it) and matching no desktop file, so
the pin's own icon would become a Python logo.

Qt is inconsistent here. The **xcb** backend builds WM_CLASS from the
application's own name (`openshot`); the **Wayland** backend uses
`QGuiApplication::desktopFileName()` and, when the app never sets one, falls
back to the basename of `/proc/self/exe` — which for a `#!/usr/bin/python3`
script is `python3`. Qt's `-name` does not override it: verified, `-name
ZZTESTCLASS` still produced `openshot`.

So `~/.local/share/applications/org.openshot.OpenShot.desktop` overrides the
system entry with `Exec=env QT_QPA_PLATFORM=xcb openshot-qt %F` plus
`StartupWMClass=openshot`, and the pinned line is `openshot`. Costs nothing
visible here — the display is scale 1, so there is no fractional-scaling blur to
inherit. Same trick as `dev.local.btop.desktop`. Delete the file to revert.

### Windows with no .desktop file get the missing-icon blob

nwg-dock draws a running window's icon by matching its **class** to a desktop
entry. No entry, no icon — you get the fallback, an orange circle with a white
X. `xdg-desktop-portal-hyprland` ships `/usr/bin/hyprland-share-picker` as a
bare binary with no `.desktop` anywhere on the system, so every time anything
asked to capture the screen (OBS, a browser, Discord) the sidebar grew a blob.

Fixed with `~/.local/share/applications/hyprland-share-picker.desktop`, which
exists *only* to make that lookup succeed — the portal spawns the binary itself,
nothing launches it from the entry. The load-bearing fields:

- `StartupWMClass=hyprland-share-picker` — what the class matches against
  (verified with `hyprctl clients`; native Wayland, not XWayland).
- `Icon=screen-shared-symbolic` — a monitor with an arrow leaving it.
- `NoDisplay=true` — keeps it out of the app grid, where a picker you cannot
  usefully start by hand would be noise. It does **not** interfere with the
  dock's icon lookup; verified both ways.

On choosing the icon: render candidates against the sidebar's own background
before picking. Papirus's `video-display` and `display` are dark-grey on a dark
sidebar and effectively invisible, and Yaru's `applets-screenshooter` reads as
"screenshot", not "share". Yaru draws its *symbolic* icons light enough to read
there, which is why a symbolic one wins here despite the sidebar otherwise being
full-colour. `video-display` (Adwaita) is the colour alternative.

Note `NoDisplay` is not visible through `Gio.AppInfo.get_all()`, which returns
hidden entries too — `should_show()` is the predicate that reflects it.

**`Nwg-drawer` had the same blob** (the app grid, `SUPER+D`) while open, for the
same reason: built from source into `~/.local/bin`, it ships no desktop entry
and runs as a normal window. Fixed the same way, with
`~/.local/share/applications/nwg-drawer.desktop`.

Two details specific to it:

- The class is **`Nwg-drawer`**, capital N — GTK capitalises the binary name.
  Read it off `hyprctl clients`; the lowercase form does not match.
- `Exec` points at `app-grid.sh`, not the bare binary, so the flags stay in one
  place. Nothing launches the drawer through this entry anyway — `SUPER+D` and
  the dock's launcher button do — and `NoDisplay` stops the app grid listing
  itself, which it otherwise would.

Its icon is `applications-other`: a blue tile with a 3x3 grid, i.e. the app-grid
metaphor in colour, which sits better among the sidebar's full-colour logos than
the flat grey `view-app-grid-symbolic` would.

### ⚠ A Claude session in the VS Code terminal has a REWRITTEN XDG environment

This cost a wrong conclusion and is worth knowing before it costs another. VS
Code here is a **snap**, and its integrated terminal inherits the snap's
sandboxed paths:

```
XDG_DATA_HOME=/home/<user>/snap/code/264/.local/share
XDG_DATA_DIRS=/home/<user>/snap/code/264/.local/share:/snap/code/264/usr/share:/usr/local/share/:/usr/share/:/var/lib/snapd/desktop
```

So `~/.local/share/applications` **is not on the search path**, and any
`gtk-launch`/`Gio.DesktopAppInfo` lookup silently resolves to the `/usr/share`
copy. Testing the OpenShot override from that shell "proved" it did not work,
when in the real session it does.

The session's own values are unset `XDG_DATA_HOME` and
`XDG_DATA_DIRS=/usr/local/share/:/usr/share/:/var/lib/snapd/desktop`. Read them
off a process Hyprland actually started, and test with them:

```bash
DOCKPID=$(pgrep -f nwg-dock-hyprland | head -1)
tr '\0' '\n' < /proc/$DOCKPID/environ | grep -E '^XDG_DATA_(HOME|DIRS)='
env -u XDG_DATA_HOME XDG_DATA_DIRS=/usr/local/share/:/usr/share/:/var/lib/snapd/desktop <cmd>
```

This applies to anything XDG-resolved — desktop entries, icon themes, MIME
defaults — not just this one test.

## The app grid (nwg-drawer, patched)

`app-grid.sh` holds the flags so `SUPER+D` and the dock's launcher button cannot
drift: `-c 7 -is 56 -fm nautilus -term ghostty -wm hyprland -ovl`.

`-wm hyprland` makes it launch apps via `hyprctl dispatch exec`, so they become
children of Hyprland rather than of the drawer and survive it closing.

Cold start ~0.6s / 79MB, so it is deliberately **not** run resident (`-r`).

fuzzel is **still needed** — the `--dmenu` pickers (cliphist, wallpaper, lock
screen) have no nwg-drawer equivalent.

Right-click gives *Open / Add-Remove favourites / Pin-Unpin sidebar*. The
drawer's favourites row is `~/.cache/nwg-pin-cache`; the sidebar's is
`~/.cache/nwg-dock-pinned`. **Do not symlink them** — the drawer stores
`<id>.desktop`, the dock needs bare classes, and mixing them resurrects the
duplicate-icon bug. The patch's sidebar entries therefore shell out to
`dock-pin.sh`, which maps a `.desktop` ID to a real class by checking, in order:
a running window matching the filename stem, then `StartupWMClass`, then
`X-SnapInstanceName`, then the snap instance name alone, then the stem.
`X-SnapInstanceName` is what makes snaps resolve while closed
(`brave_brave` → `brave`, `code_code` → `code`); matching `StartupWMClass` only
against *running* windows is deliberate, since it disagrees with the app_id.

Categories show only "All" unless the `desktop-directories` data is installed
system-wide (Part 1 step 3) — the drawer looks for it under `XDG_DATA_DIRS`,
which excludes `~/.local/share`.

## yazi

Config lives in `~/.config/yazi` (`yazi.toml`, `keymap.toml`, Catppuccin theme).
Two settings worth knowing, both in the `[mgr]` table — note the table is `mgr`,
**not** `manager`, which is what older docs and most blog posts still say; it was
renamed and this is yazi 26.9.1.

- `show_hidden = true` — dotfiles visible by default. The built-in `.` key still
  toggles it live, so the config value is only the starting state.
- `keymap.toml` uses `prepend_keymap`, which **adds to** the defaults rather than
  replacing them, so everything under `~`/F1 keeps working. Custom binds:
  `<C-o>` open in VS Code, `<A-o>` open in Files, `<C-t>` open a terminal at the
  hovered directory, and `gw` to jump to the Windows drive (`g` is yazi's
  built-in "go to" prefix, as in `gh`/`gc`).
- `<C-t>` runs `yazi-terminal.sh %s`. `%s` is the **hovered** item, which may be
  a file, so the script resolves a file to its parent and falls back to `$PWD`
  (yazi runs `shell` commands with the current directory as cwd). Two things it
  has to do that are not obvious:
  - **`--gtk-single-instance=false`.** ghostty is single-instance by default, so
    a plain second `ghostty` is handled by the already-running process, which
    inherits *that* instance's directory and silently ignores
    `--working-directory`. The same single-instance behaviour once made a
    `[workspace 3 silent]` exec rule look broken.
  - **`setsid`.** The terminal is spawned by yazi; without a new session it stays
    in yazi's process group and closing yazi can take it with it. Verified: the
    spawned pid is its own session leader.
  `~` in the `run` string is fine — yazi runs it through `sh`, which expands it.
  Substitution is `%s`, not `$@` or `$0` — `shell -- code "$@"` silently runs
  with no arguments at all.

## The wallpaper pickers

`SUPER+W` opens `wallpaper-grid.py` — a GTK3 FlowBox of thumbnails, three
columns, current wallpaper marked with a green dot. Enter or click sets it,
Escape closes. `set-wallpaper.sh` with no arguments is still the old fuzzel
name-only picker and remains the fallback.

The grid only *chooses*; `set-wallpaper.sh <path>` still does the setting, so
swaybg's start-before-kill (no black flash) and the `~/.config/hypr/wallpaper`
state file that `--restore` reads at login stay in exactly one place.

**`SUPER+SHIFT+W` is the same window with `--lock`.** One script, one `Mode`
object holding the four things that differ — title, setter, header noun, and how
"what is set now" is read. Everything else (thumbnail cache, sizing, CSS, keys)
is shared, so the two pickers cannot drift apart.

- The setter becomes `set-lockscreen.sh`, which keeps the backup / brace-check /
  restore-on-failure edit of `hyprlock.conf` in one place. The grid never
  touches that file.
- Lock mode prepends one extra tile for hyprlock's literal `screenshot` value
  (blur the live screen), first in the grid, drawn as a grey placeholder box
  since there is nothing to thumbnail. `set-lockscreen.sh screenshot` already
  handled that word, so no change was needed there.
- "Currently set" for lock mode is read back out of `hyprlock.conf`'s
  `background` block — the same block-scoped parse `--show` uses, not a state
  file. The grid opens focused on whatever is already set, in both modes.
- **Same `app_id` for both**, deliberately: `GLib.set_prgname("wallpaper-grid")`
  is unconditional, so the existing float + center `windowrule` pair covers the
  lock picker too. Do not make it mode-dependent without adding rules to match.

**It is deliberately a normal toplevel window, not a layer-shell surface.**
Layer surfaces have cost real time here — blur rules keyed on the wrong
namespace (landmine 16) and a GTK drag that froze the whole seat (landmine 13).
A plain window needs none of that: three `windowrule` blocks float and centre
it, `hyprctl clients` can see it, and `SUPER+Q` closes it like anything else.
Its `app_id` comes from `GLib.set_prgname("wallpaper-grid")`, which must run
**before** the first window is realised or the rules match nothing.

- No fixed size in the windowrule: the script computes its own from the
  wallpaper count (capped at three rows, then the ScrolledWindow takes over).
  A fixed `1020 520` left most of the window empty with only three wallpapers.
- Thumbnails are cached in `~/.cache/wallpaper-thumbs` as
  `<name>.<mtime>.png`, so replacing an image regenerates it and nothing has to
  be invalidated by hand.
- Needs `python3-gi` (installed) and PIL. Runs under `/usr/bin/python3`
  explicitly — a project venv first on PATH would otherwise shadow it.

## Optional: a BitLocker-encrypted Windows partition

> Only relevant on a dual-boot machine with a BitLocker Windows partition. On
> anything else, `mount-windows.sh` finds no such volume and does nothing; the
> `SUPER+M` / `gw` bindings can be removed. The volume label (`Windows`) and
> mount point (`/run/media/$USER/<label>`) are per machine.

Dual-boot Windows lives on a **BitLocker** partition, so it is locked at boot and
does not mount until something supplies the passphrase. That is why its dock icon
used to be absent every session: `dock-places.sh` only sees mounted volumes, and
the unlock always happened after login.

Two pieces fix it, neither needing root — udisks2 + polkit already permit the
console user to unlock and mount, which is exactly what Files does on a click:

- `mount-watch.py` (above) makes the dock icon appear the moment it mounts,
  however it was mounted — including by hand in Files.
- `mount-windows.sh` does the unlocking, from four callers:

| Caller | Mode | Behaviour |
|---|---|---|
| `exec-once` | `--boot` | Silent, never prompts, 5 tries × 4s — at login it can beat udisks2, polkit and the keyring to being ready |
| `SUPER+E` | `--ensure` | Silent, never prompts, 2 tries, backgrounded with `&` so yazi opens immediately either way |
| `SUPER+M` | `--open` | Mounts, prompting on the tty (echo off) if nothing is stored, then opens the volume in yazi |
| `gw` in yazi | none | `shell --block` so udisksctl can use yazi's terminal, then `cd` |

  The unattended modes never prompt and never print: two of them fire without
  you asking for the drive, so anything chatty would be noise at every login.
  They also exit immediately when no passphrase source exists at all, rather
  than burning their retries.

  **Every caller is serialised** on a `flock` in `$XDG_RUNTIME_DIR`. This is not
  theoretical: `SUPER+E` now unlocks in the background, so pressing `gw` a second
  later lands a second instance mid-unlock, and two concurrent `udisksctl unlock`
  calls on one device fail the loser. The lock is dropped *before* yazi is
  `exec`d — holding it would block every other caller for as long as that yazi
  stayed open.

**A logout is not a reboot, for this volume.** udisks unlocks and mounts are
system-wide, not session-scoped, so the cleartext mapping and the mount survive
logging out and back in. The disk icon is then present right after a re-login
because `dock-places.sh` finds it still mounted — which is easy to mistake for
the auto-unlock working. Only a real **reboot** (or `udisksctl lock`) puts it
back to locked, which is the state the key file exists to handle.

**Where the passphrase lives is a real security trade, not a convenience
toggle.** Two sources are tried, most secure first:

1. **The login keyring** — what this machine uses. `pam_gnome_keyring.so` is
   already in `/etc/pam.d/gdm-password` with `auto_start`, so GDM unlocks the
   keyring with your login password and `org.freedesktop.secrets` is up before
   Hyprland starts. Stored once, by you:

   ```bash
   sudo apt install -y libsecret-tools
   secret-tool store --label='BitLocker Windows volume' \
       bitlocker-uuid <uuid>
   ```

   Look it up with `secret-tool lookup bitlocker-uuid <uuid>`.

2. **`~/.config/hypr/.windows-key`**, mode 600 — plaintext, a fallback for
   machines with no keyring. `/` and `/home` here are plain ext4, so a
   passphrase in `$HOME` is readable by anyone who takes the disk out, which
   reduces BitLocker to roughly no protection at rest. The keyring does not
   have that problem: pulling the disk yields a file encrypted with your login
   password. Prefer option 1.

With neither source everything still works; it just asks once per boot. The
script never asks for or stores the passphrase itself.

**`udisksctl` takes a passphrase from a file and nothing else** — there is no
stdin or fd option — so a keyring secret has to be staged as one. It is written
to `mktemp` under `$XDG_RUNTIME_DIR`, which is tmpfs (never reaches a disk) and
mode 0700 (no other user can open it), and removed by a trap on every exit path
including signals. Do not "simplify" this to a `--key-file` in `/tmp`.

Both sources are read through command substitution, which strips trailing
newlines. That is deliberate: it makes a key file created with `echo` instead of
`printf` work, where passing the file straight to `--key-file` would have failed
with a wrong-passphrase error and no hint why.

Two implementation notes that cost time:

- **`lsblk <device>` prints nothing here** — not an error, no message, exit 0 —
  because this user is not in the `disk` group and lsblk cannot open the node.
  Locating the unlocked volume therefore reads `/sys/class/block/<part>/holders/`,
  which needs no privileges. `lsblk` with *no* device argument works fine, so
  this is easy to miss.
- The script must call yazi by **absolute path**: keybind children get no
  `~/.local/bin` on PATH, so a bare `yazi` dies with "not found" (the same trap
  as `$fileMgr` in hyprland.conf).

If a mount ever fails mentioning hibernation, that is the ntfs driver refusing a
dirty volume — turn Fast Startup off in Windows rather than forcing it.

## The network panel

Clicking the bar's Wi-Fi icon used to run `nm-connection-editor`, which by
design only edits **stored profiles** — it never scans, so there was no way to
join a network you had not joined before. nm-applet is running and its own menu
can do that, but that menu hangs off the tray icon's StatusNotifierItem, not the
`network` module. `network-panel.py` gives the one obvious click target both
halves; right-click still opens the bare editor.

| Tab | Does |
|---|---|
| Available | `nmcli dev wifi list`, deduped to one row per SSID; connect, disconnect, Wi-Fi radio toggle, rescan |
| Saved | `nmcli con show`; connect, disconnect, forget, and Add/Edit which hand off to nm-connection-editor |

Four things here are not obvious, and three of them were found by testing:

- **`nmcli -t` escapes `:` inside values as `\:`.** A plain `split(":")` shreds
  every BSSID (`54\:F0\:B1\:…`) and every `TIMESTAMP-REAL` (`01\:59\:24 PM`).
  `split_terse()` walks the string honouring the backslash. Verified against
  this machine's output, not defensive coding.
- **The AP list is one row per BSSID, not per network.** A dual-band router
  appears twice with different signal, so the panel keeps the strongest per
  SSID — while carrying the `IN-USE` flag across, because you can be joined to
  the *weaker* band of a network you also see stronger. That is the real case
  here: the joined network is in use at 82% on 5GHz while its 2.4GHz radio reads 84%.
- **NetworkManager ages APs out of its scan cache.** Measured: 7 networks in the
  cache, 2 left a couple of minutes later — a panel that trusted the cache
  looked broken, showing only the strongest one or two. So it renders the cache
  immediately (never a blank window) and then rescans exactly once, tracked by
  `did_initial_rescan`. Not on every refresh: every completed action refreshes
  too, and rescanning there would add seconds to each connect.
- **One status line serves both tabs**, so each list reports on the *visible*
  tab when it reloads, not on itself. An earlier version instead skipped the
  write when its tab was hidden — which left `Scanning…` stuck on screen
  forever, because `set_busy(False)` does not clear the text. It must always
  write something.

**No passphrase reaches argv.** `/proc` is world-readable, so
`nmcli … password <secret>` would expose a Wi-Fi passphrase to every local user
for the life of the call. Secrets go to `nmcli --ask` on **stdin**.

Verified end to end on 2026-09-18 by forgetting a known hotspot and rejoining
it. The NetworkManager journal is what makes it conclusive, because the obvious
failure mode is invisible from the UI — nm-applet is also running and registers
its own secret agent, so it could have popped its own dialog and supplied the
key with this panel never in the loop. It did not:

```
14:56:32  op="connection-delete"  name="MyHotspot"  result="success"   <- Forget
14:57:31  agent[:1.314/nmcli-connect/1000]: agent registered           <- nmcli, NOT nm-applet
14:57:31  op="connection-add-activate"  name="MyHotspot"               <- `dev wifi connect`
14:57:32  'MyHotspot' has security, and secrets exist. No new secrets needed.
14:57:41  Connected to wireless network "MyHotspot"
```

"secrets exist, no new secrets needed" is the line that matters: NM never had to
ask any agent, because nmcli had already been given the passphrase — on stdin.
The later `auto-activating connection 'MyHotspot'` proves it was *stored*
correctly too, not merely used once.

Still unexercised, all low-risk: joining an **open** network, the 802.1X handoff,
and the Wi-Fi radio toggle.

**802.1X is handed off deliberately.** Networks like `eduroam` need an EAP
method, an identity and sometimes a CA certificate — a form, not a password
box — so a first-time join opens nm-connection-editor instead of pretending one
entry field is enough. Once saved they connect from either tab like anything
else.

**The accent is read at runtime** from `theme/accent`, not templated in. That
keeps this file out of the twelve-file manifest: no snapshot, no `--resync`
after editing it, and no chance of a render overwriting a later edit. Contrast
`wallpaper-grid.py`, which *is* templated and does need the resync dance.

⚠ `hyprland.conf` and `waybar/config.jsonc` **are** in the manifest, and wiring
this panel up edited both. `set-accent.sh --resync` was run; skipping it would
have meant the next accent change silently reverted the windowrules and the
`on-click`.

## VS Code, themed

VS Code shipped with **no colour theme installed at all** — stock Dark+ (`#1f1f1f`
base) against ghostty and yazi's Catppuccin Mocha (`#1e1e2e`). That single
missing extension was the entire reason the editor looked foreign.

Now: `Catppuccin.catppuccin-vsc` + `catppuccin-vsc-icons`, `Catppuccin Mocha`,
JetBrainsMono Nerd Font with ligatures (`editor.fontLigatures` matches ghostty's
`font-feature = calt, liga`), and `window.titleBarStyle: custom` so the window
is themed edge to edge instead of wearing a grey GTK bar.

`.config/Code/User/settings.json` is in set-accent.sh's manifest, so
`SUPER+ALT+C` recolours the IDE chrome. Four things here are not obvious:

- **Only the chrome follows the accent — 49 keys, not all 79.** The theme tints
  79 colours with the accent, but most are *semantic*:
  `editorBracketHighlight.foreground6`, `symbolIcon.keywordForeground`,
  `charts.purple`, the gitlens graph lanes. Repainting those would recolour
  language keywords and bracket pairs — exactly what the `.tmTheme` files are
  excluded from the manifest to avoid. Pick green and your brackets go green.
  So the override list is deliberately the chrome you read as "the accent".
- **`catppuccin.accentColor` stays at its default `mauve`.** It takes a palette
  *name*, not a hex, so it cannot be templated. Its default happens to be the
  colour set-accent.sh calls `ORIGINAL`, which means the ~30 accent-tinted keys
  the manifest does *not* override still agree with the ones it does whenever
  the accent is the stock one.
- **Alpha suffixes survive the token.** Ten of the keys are translucent —
  `selection.background` is `…66`, the minimap slider `…33/66/99`,
  `tab.unfocusedActiveBorderTop` `…4d`. The token replaces only the six hex
  digits, so `@@ACCENT@@66` renders `#89b4fa66` and the tint stays a tint. Write
  a bare hex there and a subtle wash becomes a solid block. Same mechanism as
  `rgba(cba6f7ee)` in hyprland.conf.
- **It is the only managed file that rewrites ITSELF.** Every other entry in the
  manifest is edited by humans only; VS Code writes `window.zoomLevel` back when
  you press `Ctrl+=`. So the `--resync` rule has teeth here that it does not
  have elsewhere: change a setting in the GUI, then run `--resync`, or the next
  accent pick reverts it. The file says so at the point of use.

### Runaway ripgrep: $HOME as the workspace folder

Symptom: `rg` pegged at **>1000% CPU** (multi-core; `top` showing "55%" is one
core's worth) and never finishing. Two of them, both children of VS Code's
extension host, with `cwd = $HOME`.

The cause is that **$HOME is open as the workspace folder**, so VS Code's file
indexer crawls the entire home directory:

| | inodes |
|---|---|
| `snap` | 144,193 |
| `miniforge3` | 108,087 |
| `miniconda3` | 106,568 |
| `.cache` | 45,034 |

— and `.vscode-server`, `ROCmFuzz` and `.texlive2025` were too large to finish
counting. Worse, the command line was `rg --files --hidden --no-ignore --follow`:
`.gitignore` disabled *and* symlinks followed. A conda prefix is a forest of
symlinks (`lib/libX11.so.6 -> libX11.so.6.4.0`, thousands of them), so `--follow`
walks the same targets repeatedly — which is why it burned CPU rather than I/O
(133MB read in 3m40s while saturating cores).

**Killing it is not a fix.** The extension host respawned a fresh `rg` within two
seconds, at 856% CPU. The only thing that holds is removing the work:

- `search.followSymlinks: false` — the single biggest win, for the conda reason
  above.
- `search.exclude` + `files.watcherExclude` for the heavy trees. Both lists are
  needed and they are separate costs: the indexer crawls, and the watcher takes
  an inotify watch *per directory*, which on a tree this size is slow to set up
  and can exhaust the per-user watch limit.
- `files.exclude` was deliberately NOT used — it hides folders from the Explorer
  entirely, which is a bigger change than the problem warrants. The excluded
  trees stay visible and browsable, they are just not crawled.

The real cure is to open project folders rather than `$HOME`; the excludes make
`$HOME` survivable, not correct.

Note these settings live in the same managed `settings.json`, so they were added
to the live file and pushed into the template with `--resync` (which reported
`1 updated` and left all 49 accent tokens intact). That is the right direction
for lines with **no** accent hex in them — see the trap below for lines that do.

### Two traps when editing a managed file, found the hard way

- **Add new accent-bearing lines to the TEMPLATE, not the live file.**
  `--resync` deliberately replays a *diff* rather than pattern-matching colours
  (see its comment about yazi's 140 green occurrences). That is right for edits,
  but it means a brand-new line containing the current accent hex is baked into
  the template *literally* — frozen at that colour forever, silently. New accent
  keys go into `theme/templates/vscode-settings.json` as `@@ACCENT@@`, then
  render.
- **Never write the accent hex in prose inside a managed file.** `init()`
  tokenises every occurrence of `ORIGINAL`, comments included. A comment reading
  "the default accent is mauve (#cba6f7)" came back after the first render as
  "mauve (#89b4fa)" — documentation rewritten into a falsehood. Name the colour,
  do not spell it.

Verified by round trip: set the accent to green, all 49 keys followed and every
alpha suffix survived; set it back to blue, all 49 followed again.

## Workspaces behave like a stack

`workspace-stack.py`. Hyprland destroys an empty workspace but never renumbers
the survivors, so closing the last window on 2 leaves you with 1, 3, 7. The
daemon listens on `.socket2.sock` and moves windows so occupied workspaces are
always 1..N with no holes — like pages of apps on a phone.

- `RESERVE_ACTIVE = True` keeps the workspace you are *standing on* even while
  empty, so "switch to an empty workspace, then launch something" still works.
  `False` gives strict compaction, but then the next occupied workspace is pulled
  on top of you the moment you arrive somewhere empty. Either way, an empty
  workspace you are not looking at is closed up.
- It talks to the IPC socket directly rather than shelling out to `hyprctl`: one
  compaction is a dozen commands, and `exec-once` children get a PATH where
  `python3` may be a venv (hence `/usr/bin/python3` in the exec-once).
- Moves use `movetoworkspacesilent`, then one explicit `workspace` dispatch, so
  focus follows the windows instead of stranding you on what is now empty.
- It **skips multi-monitor setups entirely**. Workspace ids are global but each
  belongs to a monitor, so compacting would drag windows across screens. A second
  display needs rethinking, not just enabling.
- Special workspaces (scratchpad, negative ids) and pinned windows are excluded.
- Its own moves re-trigger the event, so the recompute must stay idempotent —
  identical input must produce zero dispatches, or it loops forever.

## Screenshots

`SUPER+SHIFT+S` region / `Print` screen / `SHIFT+Print` window, all through
`screenshot.sh`: saves to `~/Pictures/Screenshots/<timestamp>.png`, copies to the
clipboard, and notifies.

The old binds were a bare `grim - | wl-copy` on all three keys — they worked, but
wrote no file, did no region select and showed nothing, so they were
indistinguishable from a dead keybind, while CHEATSHEET.md had been promising
"screenshot a region" the whole time.

**When a keybind is reported broken, check what it actually does before assuming
it never fires:** `hyprctl binds` shows what Hyprland registered, and
`hyprctl dispatch exec '<cmd>'` runs exactly what the bind would.

- The script refuses to hand over an all-black capture (landmine 10).
- `slurp` exiting non-zero means Escape was pressed. A normal cancel, not an
  error — exit quietly, do not notify.
- **Never capture the output of anything that runs `wl-copy`.** It forks and keeps
  the clipboard alive, holding whatever stdout it inherited, so a pipe never
  reaches EOF and the caller blocks forever. Redirect to a file, which is what
  Hyprland's own `exec` does.

## VS Code looks smaller than everything else

Not a misconfiguration — a consequence of a dense panel at `scale 1` (the
reference machine: 1920×1200 on 14", **~162 DPI**), where nothing is scaled
up at all. VS Code then sizes its chrome in raw pixels while GTK apps size theirs
in points:

| | rendered | physical |
|---|---|---|
| VS Code UI (default 13px) | 13px | 2.0 mm |
| GTK apps (`Ubuntu Sans 11`) | 14.7px | 2.3 mm |

Its icons are 16px sprites, which is why they look small too — so
`editor.fontSize` is the wrong knob, as it only touches code text and leaves the
icons, tabs and sidebar alone. **`window.zoomLevel` scales all of it together**;
each step is 1.2x. `~/.config/Code/User/settings.json` sets `1` (120%), which
puts the UI font at 15.6px, just above GTK's 14.7px.

```jsonc
"window.zoomLevel": 1,
"editor.fontSize": 14,
"terminal.integrated.fontSize": 14,
```

`Ctrl+=` / `Ctrl+-` change it live and VS Code writes the value back into that
file, so it is the user's knob, not a fixed choice. The settings file takes
JSONC comments, and the reasoning is recorded in it.

Verify a zoom change actually landed by measuring the **activity bar**, not the
font: it is 48px wide at zoom 0, so at `zoomLevel: 1` it must read 58px.

```bash
grim -g "<window x>,400 400x1" /tmp/strip.png   # one pixel row across the rail
```

Two things this is **not**:

- Not XWayland. VS Code does run under XWayland here (`hyprctl clients` reports
  `xwayland=True`) because the snap does not inherit
  `ELECTRON_OZONE_PLATFORM_HINT`. At `scale 1` both paths render 1:1, so it has
  no bearing on size — it would only matter if the monitor scale were raised.
- Not something to fix compositor-side unless *everything* feels small. The
  broader lever is `monitor=<output>,preferred,auto,1.25`, which scales the whole
  desktop but blurs XWayland clients. Per-app zoom is the cheaper trade.

## PATH

`exec-once` children get PATH **without `~/.local/bin`**. Use absolute paths in
keybinds and in the dock's `-c` for anything installed there (nwg-drawer, yazi,
zellij) or it silently fails.

---

# Part 4 — Working on this system

## Testing from inside VS Code — read before debugging

Claude Code often runs inside the **VS Code snap**, whose environment is polluted
and will produce false failures:

| Variable | Snap value | Breaks |
|---|---|---|
| `XDG_DATA_HOME` | `~/snap/code/NNN/.local/share` | font lookup, `.desktop` lookup |
| `GDK_BACKEND` | `x11` | waybar: *"Bar need to run under Wayland"* |
| `GSETTINGS_SCHEMA_DIR` | snap's schemas | waybar: fatal GLib schema error |

Prefer `hyprctl dispatch exec` (landmine 12) — the child then inherits Hyprland's
own environment *and* lands in the right cgroup. For a one-shot GUI tool run
directly from a tool call, scrape a clean environment instead:

```python
env = {}
src = subprocess.run(["pgrep","-x","mako"], capture_output=True, text=True).stdout.split()[0]
for kv in open(f"/proc/{src}/environ","rb").read().split(b"\0"):
    if kv and b"=" in kv:
        k, v = kv.split(b"=", 1)
        env[k.decode()] = v.decode(errors="replace")
```

Do **not** export these on top of the current environment — variables the clean
env does not define (like `GSETTINGS_SCHEMA_DIR`) survive and still break things.
Pass the dict as the child's whole environment.

## Verify visually, not by inference

`grim` is installed. When something "doesn't render", screenshot it:

```bash
hyprctl layers                      # find the surface + its exact geometry
grim -g "X,Y WxH" out.png           # capture precisely that
```

This is how both waybar bugs were found. Neither logs anything.

Measuring by heuristic has produced **three** wrong conclusions in this project:
the dock's surface width drifting as GTK re-measures, an "icon band" counter, and
a "lowest icon row" detector that was reading the panel's border. Crop the region
and look at it.

`hyprctl clients` lists **windows only**. Bars, docks, the launcher and the
wallpaper are *layer-shell surfaces* and appear only in `hyprctl layers`. That is
also why `SUPER+Q` (`killactive`) does nothing to them.

## Applying a config change without logging out

Almost nothing here needs a logout; what differs is *how* each piece picks up an
edit. `~/.config/hypr/reload.sh` does the right thing per target.

| Edited | Picks it up by | Command |
|---|---|---|
| `hypr/hyprland.conf` | live reload | `hyprctl reload` (or `reload.sh`) |
| `waybar/config.jsonc`, `waybar/style.css` | **restart, bar before dock** | `reload.sh bar` |
| `nwg-dock-hyprland/style.css`, dock flags in `dock-start.sh` | restart | `reload.sh dock` |
| `hypr/hypridle.conf` | restart (no reload verb) | `reload.sh idle` |
| mako config | live reload | `makoctl reload` |
| `hypr/hyprlock.conf` | nothing — read at lock time | — |
| `nwg-drawer/`, `nwg-bar/` | nothing — spawned per invocation | — |
| `yazi/*.toml` | next yazi start | quit and reopen |
| `hypr/dock-icons.conf` | run the applier | `dock-icons.sh` |
| `~/.cache/nwg-dock-pinned` | live (patched dock watches it) | — |
| `Code/User/settings.json` | live (VS Code watches it) | — |

Two traps the table exists to encode:

- **Never restart waybar on its own** — it comes back narrower (landmine 11).
  `reload.sh bar` kills both, starts waybar, waits for its layer, then starts the
  dock, and checks the resulting geometry starts at `x=0`.
- **`hyprctl reload` does not re-export `env =` lines** to processes that are
  already running. New children get the new value; the bar, dock and daemons
  started at login keep the old one until they are restarted.

`reload.sh` verifies the config before reloading and refuses on a parse error,
so a typo cannot take the session down mid-edit.

## Sanity check after any change

```bash
Hyprland --verify-config -c ~/.config/hypr/hyprland.conf   # must print "config ok"
hyprctl reload                                             # apply without logout
hyprctl layers | grep namespace                            # bar/dock/wallpaper present?
hyprctl layers | grep -c "pid: -1"                         # must be 0
for p in waybar swaybg mako hypridle nwg-dock-hyprla; do
  printf "%-18s %s\n" "$p" "$(pgrep -x "$p" | tr '\n' ' ')"
done                                                       # ONE waybar
for n in workspace-stack.py mount-watch.py; do                # both daemons
  printf "%-20s %s\n" "$n" "$(ps -eo pid,comm,args | grep -F "$n" \
    | awk '$2=="python3"{print $1}' | tr '\n' ' ')"
done
```

After a fresh **login** specifically, run `~/.config/hypr/postlogin-check.sh` —
it ends in a verdict on the two surfaces. The bar is expected at
`0 0 <screen width> 40` (42 in the islands style), the width read from
`hyprctl monitors`, so changing the bar's margins without updating that check
makes it cry wolf — it did exactly that once. The dock's checks are derived instead of
hardcoded (x=6, w=78, shorter than the usable strip, centred ±4px), because its
height tracks the pin count and disks come and go with mounts.

`pgrep` takes **one** pattern only — `pgrep -a waybar swaybg mako` errors out.
And `pgrep -f workspace-stack` matches the shell running it (landmine 7).

Check for duplicate keybinds — Hyprland accepts them silently:

```bash
grep -E "^\s*bind[elm]*\s*=" ~/.config/hypr/hyprland.conf \
  | sed -E 's/^\s*bind[elm]*\s*=\s*//' \
  | awk -F',' '{gsub(/^ +| +$/,"",$1);gsub(/^ +| +$/,"",$2);print $1"|"$2}' \
  | sort | uniq -d
```

After touching anything in `patches/`, confirm the patch still applies to a
pristine checkout before trusting it:

```bash
git clone --depth 1 https://github.com/nwg-piotr/nwg-dock-hyprland.git /tmp/verify
cd /tmp/verify && patch -p1 --dry-run < ~/.config/hypr/patches/nwg-dock-hyprland-0.4.11-local.patch
```

## Things deliberately not done

- **Centred sidebar icons** — implemented, reverted on request; icons pack from
  the top.
- **GTK drag-and-drop in the dock** — see landmine 13. Replaced by the
  pointer-tracking `-reorder`.
- **Drag-and-drop reordering of waybar modules** — asked for, not delivered.
  waybar 0.15.0 has no such feature: `man 5 waybar` mentions neither drag nor
  reorder anywhere across its 54 pages, and module order comes solely from the
  `modules-left/center/right` arrays in `config.jsonc`. Adding it would mean
  building waybar from source (C++/meson, unlike the two Go tools) *and* adding
  drag handling to heterogeneous module widgets *and* writing the new order back
  into the JSON. Worse, waybar is a layer-shell surface, so real GTK
  drag-and-drop would reproduce landmine 13 — the seat-wide grab that froze the
  desktop — and the pointer-tracking workaround used for the dock would have to
  be rebuilt in C++. Reordering is a one-line edit of the array plus a restart
  (waybar first, then the dock — landmine 11).
- **Multi-monitor** — the workspace stacker refuses to run with more than one
  output, and the dock/bar geometry here assumes a single display.
