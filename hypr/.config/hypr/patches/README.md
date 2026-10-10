# Local patches

Patches applied to software built from source into `~/.local/bin`. They are kept
here because a rebuild from a fresh upstream checkout loses them silently — the
program still compiles and runs, it just quietly goes back to upstream behaviour.

## nwg-drawer-0.7.5-context-menu.patch

Gives the app grid (`SUPER+D`) a real right-click context menu.

Upstream 0.7.5 has no menu: right-clicking an app toggles it in the drawer's own
favourites row straight away, which is why apps seemed to "jump to the top".
The patch replaces that with:

    Open
    ─────────────────────────
    Add to / Remove from favourites     -> ~/.cache/nwg-pin-cache  (drawer row)
    Pin to / Unpin from sidebar         -> ~/.cache/nwg-dock-pinned (nwg-dock)

The two lists are deliberately separate. The drawer stores `<id>.desktop`; the
dock stores bare window **classes**, and mixing them causes the duplicate-icon
bug (see the Brave entry in `~/Hyprland_CLAUDE.md`). The sidebar half therefore
delegates to `~/.config/hypr/dock-pin.sh`, which resolves a `.desktop` ID to the
real class. Keep that script in place — the patched binary shells out to it by
absolute path.

### Menu lifetime (second half of the same patch)

The menu half above, as first written, built a fresh `gtk.Menu` on every
right-click and never destroyed it. That showed up as two separate complaints:

* **Tiles stayed "selected".** A GtkMenu takes a pointer grab while it is up,
  so the tile under the cursor never gets its `leave-notify-event` and stays
  stuck in `PRELIGHT`. Nothing ever cleared it, so every app you right-clicked
  stayed lit and they piled up for the lifetime of the drawer.
* **The grid got slower.** Each of those menus leaked — a GtkMenu plus its
  items, plus a reference on the tile it was attached to.

`popupAppMenu()` now owns the single live menu: it pops down and destroys the
previous one, clears the forced state flags on the tile that one was attached
to, and hooks `deactivate` (Escape, click-away, or an item chosen) to do the
same for itself.

Two things to preserve if this ever needs reworking:

* Destruction goes through `glib.IdleAdd`, not an inline `Destroy()`. On the
  `deactivate` path you are inside the menu's own signal emission, and freeing
  the widget there risks GTK touching memory it just dropped. Idle also runs
  *after* a chosen item's `activate` handler, so Open / favourites / sidebar
  still fire.
* The old tile is cleared **before** the new one is adopted. That ordering is
  the whole fix for the pile-up.

### Rebuilding after an upstream update

```bash
git clone https://github.com/nwg-piotr/nwg-drawer.git
cd nwg-drawer
git checkout v0.7.5                 # or newer; expect the patch to need rework
patch -p1 < ~/.config/hypr/patches/nwg-drawer-0.7.5-context-menu.patch
gofmt -w tools.go uicomponents.go
go vet ./...
go build -o nwg-drawer .            # ~15 min cold: gotk4's cgo bindings
install -m755 nwg-drawer ~/.local/bin/nwg-drawer
```

Build deps are the same ones nwg-dock needed: `golang-go libgtk-layer-shell-dev
libgtk-3-dev pkg-config libgirepository1.0-dev`.

If the patch no longer applies, the two hunks to redo are the
`btnEvent.Button() == 3` branches in `uicomponents.go` (one in
`setUpPinnedFlowBox`, one in the main grid tile builder) plus the three
`dockPin*` helpers in `tools.go`.

## nwg-dock-hyprland-0.4.11-local.patch

Six changes to the sidebar. Rebuild instructions at the end. Base: upstream
commit `028ad56` (the v0.4.11 tag itself rejects one hunk).

### 1. Watch the pinned file

`buildMainBox()` re-reads `~/.cache/nwg-dock-pinned`, but it is only ever called
from `refreshMainBox(true)`, whose sole caller is the `activewindowv2` branch of
the socket2 loop, guarded on the window address having changed. So a pin edited
from anywhere else — the drawer's "Pin to sidebar", `dock-places.sh`, a hand
edit — did not show until you next focused a **different window**. That is why
"Unpin from sidebar" looked like it did nothing: the file was already correct,
the pixels were stale. `SIGRTMIN+2` does not help either; `WindowShow` only
calls `win.ShowAll()`.

An fsnotify watcher now rebuilds on change. Two details:

* It watches the **directory**, not the file — the helper scripts replace it
  with `mv`, which swaps the inode and would silently kill a file watch.
* The debounce is **trailing-edge** (`time.AfterFunc`, reset per event). The
  first attempt rebuilt on the first event and dropped everything within 150ms,
  racing the writer: the dock rendered the previous contents and sat one change
  behind. Rebuild only once the file is quiet.

Adds `github.com/fsnotify/fsnotify`.

### 2. Launcher fixed to the bottom

With `-lp end` upstream only packs the launcher *after* the last icon, so it
floats mid-dock. The patch uses `PackEnd` and, when `-f` is combined with
`-lp end`, lets `mainBox` expand to the full height so `PackEnd` actually
reaches the bottom edge.

It also gives the launcher widgets CSS names (`#launcher-box`, `#launcher-button`)
via `SetObjectProperty("name", …)`. **Upstream sets no widget names at all** —
the `#launcher-button` rules that style.css has always carried were dead. The
separator line lives on `#launcher-box`, the full-width row; putting it on the
button would only span the icon.

### 3. A bottom group (`-bottom`)

`-bottom dock-disk-,dock-trash` takes a comma-separated list of pin-name
**prefixes**. Matching pins are packed into a `bottomBox` together with the
launcher, and that box is `PackEnd`ed to the foot of the dock — so Trash and the
mounted disks sit directly above the grid button instead of trailing the app
icons. Routing is by prefix, not by position in the pinned file: moving
`dock-trash` to line 3 still renders it in the bottom group (it only changes its
order *within* that group, since the group is packed in file order).

The separator moved from `#launcher-box` to `#bottom-box` so the line sits above
all three icons. That row is anchored to the bottom, so its `padding-top` is
literally the gap between the line and the first icon below it.

### 4. Drag-to-reorder (`-reorder`)

**Read "Why the first drag-and-drop attempt was reverted" below before touching
this.** The short version: this implementation uses no GTK drag-and-drop at all.

`makeReorderable` connects plain `button-press-event`, `motion-notify-event` and
`button-release-event`. A press records the source pin, movement past an 8px
threshold marks it a drag, and the release finds the icon under the pointer by
comparing the pointer's y against each button's `Allocation()`. A real drag
returns `true` from the release handler so the app is not launched; anything
shorter falls through and behaves as a normal click.

Why this cannot freeze the session: there is no `start_drag`, so no seat-wide
drag grab. The only grab involved is the implicit pointer grab any button press
takes, which the compositor releases on button-up regardless of what the handler
does. Worst case is a wrong reorder or a swallowed click.

Excluded from reordering: the `-bottom` pins, the launcher, and any running app
that is not pinned (no line in the file to move).

The handlers are connected **before** upstream's own release handler, which is
what lets a drag swallow the click — `makeReorderable` is therefore called early
in `pinnedButton`/`taskButton`, before their existing `Connect` calls.

Gated behind `-reorder`, off by default: **drop that one word from the dock's
arguments in `hyprland.conf` and `dock-toggle.sh`, restart the dock, and the
feature is gone — no rebuild.**

### 5. Per-app icon overrides (`-icondir`)

`-icondir DIR`: `createImage()` first tries `DIR/<id>.svg`, then `.png`, where
`<id>` is the pinned entry or the running window's class — before any
`.desktop` / icon-theme lookup. It is how the dock gets its Catppuccin Mocha
glyph icons (`~/.config/hypr/dock-theme-icons.py` writes them to
`~/.local/share/nwg-dock-hyprland/mocha-icons`, `dock-start.sh` passes the
flag) without touching the `.desktop` files that the app grid and fuzzel read
— `dock-icons.sh` is the other way, and it changes those everywhere. No file
for an id = the normal icon.

### 6. Indicator width (`-indicator`)

The running-app indicator (`images/task-*.svg`, drawn beside each icon) is
`-i / 8` px thick upstream — 3px at `-i 30`, too thin to see. `-indicator N`
sets it (`indicatorSize()`); dock-start.sh uses 5 with 4px accent bars.
Also: those SVGs must start with the `<svg>` tag. gdk-pixbuf only sniffs the
start of the file, a long leading comment makes it fail, and when the
indicator fails to load the dock drops that app's whole button.

### Rebuilding

```bash
git clone https://github.com/nwg-piotr/nwg-dock-hyprland.git
cd nwg-dock-hyprland
git checkout 028ad56
patch -p1 < ~/.config/hypr/patches/nwg-dock-hyprland-0.4.11-local.patch
GOFLAGS=-mod=mod go get github.com/fsnotify/fsnotify@v1.9.0
gofmt -w main.go tools.go && go vet ./...
go build -o nwg-dock-hyprland .
install -m755 nwg-dock-hyprland ~/.local/bin/nwg-dock-hyprland
```

Check change 1 took with `-debug`: the log should say
`Watching /home/<user>/.cache for changes to …/nwg-dock-pinned`.

## Why the first drag-and-drop attempt was reverted

Drag-to-reorder was implemented (pinned icons as GTK drag sources and drop
targets, the drop rewriting the pinned file) and then **removed**, because
starting a drag froze the entire desktop — the session had to be logged out of
to recover. It has since been replaced by the pointer-driven `-reorder` above, which
never calls `start_drag`.

What happens: a Wayland drag is `wl_data_device.start_drag`, which puts the
whole **seat** into a drag grab. Until the drag ends, every pointer event goes
to the drag and nothing else on the desktop reacts. The dock is a **layer-shell**
surface with no keyboard interactivity, so `Escape` cannot reach it to cancel —
the usual escape hatch does not exist. Anything that stops the drop completing
therefore leaves a permanent seat-wide grab, which is exactly what "the whole
environment becomes inactive" is.

Nothing crashes, which is why there is no panic in any log: the dock keeps
running and the compositor stays responsive to the keyboard. `pkill -x
nwg-dock-hyprla` releases the grab (`SUPER+A` brings it back).

So: **do not add GTK drag-and-drop to a gtk-layer-shell surface.** Track the
pointer manually instead, as change 4 does.

## Landmines when testing these patches

Three ways a rebuild or a test can lie to you. All three cost real time during
the 2026-09-17 drawer work.

### The VS Code terminal is snap-confined and misreports XDG paths

Anything launched from the integrated terminal in the VS Code **snap** inherits
the snap's view of the world:

```
XDG_DATA_HOME=/home/<user>/snap/code/259/.local/share
XDG_DATA_DIRS=/home/<user>/snap/code/259/.local/share:...:/usr/local/share/:/usr/share/
```

`XDG_DATA_HOME` is redirected and `~/.local/share` is **absent** from
`XDG_DATA_DIRS`. So `.desktop` lookups that work fine in the real session fail
there — `gtk-launch dev.local.btop` returns "no such application" — and the
drawer resolves a different data dir than it will at login. That is a **false
negative**, not a bug in the thing you just changed.

Test with the session's real environment:

```bash
env -u XDG_DATA_HOME \
    XDG_DATA_DIRS=/usr/local/share/:/usr/share/:/var/lib/snapd/desktop \
    gtk-launch <id>
```

The authoritative values are always readable from a process Hyprland started:

```bash
tr '\0' '\n' < /proc/$(pgrep -x nwg-dock-hyprla)/environ | grep ^XDG_
```

Note `pgrep -x nwg-dock-hyprla` — the 15-char truncation, same as in
`dock-toggle.sh`.

### ghostty silently ignores an invalid `--class`

`--class` must be reverse-DNS (GTK application-ID form, at least two dots).
`--class=btop` is accepted on the command line, does nothing, and the window
comes up as `com.mitchellh.ghostty`; `--class=dev.local.btop` works. There is
no warning either way, so verify with `hyprctl clients` rather than trusting
the flag. This is why `~/.local/share/applications/dev.local.btop.desktop`
uses the dotted name — the pinned line in `~/.cache/nwg-dock-pinned` has to
match the real window class or the dock can never show a running indicator.

### `pkill -f` kills the shell you are typing in

Already called out in `dock-toggle.sh`, and still easy to walk into: `-f`
matches whole command lines, so `pkill -f btoptest` signals any shell whose
command line merely mentions it. Close test windows through the compositor
instead:

```bash
hyprctl -j clients | python3 -c "import json,sys; [print(c['address']) for c in json.load(sys.stdin) if c['class']=='<class>']"
hyprctl dispatch closewindow address:<addr>
```

## Not in this directory

Two related fixes are **not** patches — do not come looking for them here:

* **Drawer category filters** (the row of Accessories / Graphics / … above the
  grid). Pure configuration: the `.directory` files live in
  `~/.local/share/nwg-data/nwg-drawer/desktop-directories/` and
  `app-grid.sh` prepends that dir to `XDG_DATA_DIRS`. Rationale, and why it
  must be a dedicated directory rather than `~/.local/share`, is in
  `app-grid.sh` and in `~/Hyprland_CLAUDE.md`.
* **btop in the sidebar.** A `.desktop` override, not a code change. The
  system entry is `Terminal=true` and nwg-dock has no terminal option, so it
  execs `btop` with no TTY and btop exits immediately. See
  `~/.local/share/applications/dev.local.btop.desktop`.
