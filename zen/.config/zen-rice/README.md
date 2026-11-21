# Zen: live desktop theme + accent

Firefox follows SUPER+ALT+C (accent) and SUPER+SHIFT+T (theme) live through
the Rice Accent extension and Firefox's theme API. Zen ignores Firefox themes,
and its own live accent is a pref (`zen.theme.accent-color`) nothing outside
the browser can set. So Zen gets an **autoconfig** script instead: privileged
JavaScript Zen runs from its install directory at every start.

| File | Goes to | Does |
|---|---|---|
| `autoconfig.js` | `~/.local/opt/zen/defaults/pref/` | tells Zen to run `rice-live.cfg` (unsandboxed) |
| `rice-live.cfg` | `~/.local/opt/zen/` | loads every `*.uc.js` here into each browser window (through a `resource://rice-uc/` alias — `loadSubScript` refuses `file:` URLs), and once a second, stats `~/.config/hypr/theme/accent` and `palette.json`; on change sets `--rice-accent`, `--rice-base`, … on every Zen window and its bookmarks/history sidebar, and registers a small user sheet with the same variables for Zen's own pages (new tab, settings, about:), which run in content processes |

`build/zen.sh` copies both in after every install/update (the install dir is
replaced each time). The colours are used by Zen's `chrome/userChrome.css` and
`chrome/userContent.css` (`~/.config/hypr/theme/templates/zen-user*.css`,
rendered by `set-accent.sh`) as `var(--rice-…, <rendered hex>)`.

Re-registering a re-rendered userContent.css does NOT work: a style-sheet
service user sheet sorts before the profile's own userContent.css, so the
startup copy keeps winning. Variables from a separate sheet sidestep the order.

Changes need one Zen restart to load the script; after that, accent and theme
changes show within a second. `RICE_THEME_DIR=/some/dir` in Zen's environment
points the script at another theme directory (tests). Errors go to the Browser
Console (`rice-live.cfg: …`).

Tested headless (scratch profile, RICE_THEME_DIR): writing a new accent
recoloured `--zen-primary-color`, the URL bar ring and the bookmarks panel
within 1.6 s; an open about:newtab followed a new accent within 2 s without
reloading (links, primary buttons, --color-accent-primary).

## Tiling workspaces (`tiles.uc.js`)

The desktop's workspace model inside Zen. A workspace = one entry of the tab
list: a tab, or a Zen split view. Keys and picker are listed at the top of the
file (and in `hypr/CHEATSHEET.md`). Loaded straight from this folder by
`rice-live.cfg`, so editing it needs only a Zen restart (no `build/zen.sh`).

- `Ctrl+T` adds a tile with dwindle placement: `splitTabs()` appends the tab to
  the split's root, then the leaf is moved next to the focused tile with Zen's
  own `removeNode()` / `splitIntoNode()` and the tree is normalised (no node
  with its parent's direction, no one-child nodes) before re-layout.
- Placement follows Hyprland's dwindle (force_split 0): the tile under the
  cursor (tracked with a chrome `mousemove` listener — it fires over web pages
  too) splits side by side if wider than tall, else stacked, and the new tile
  takes the cursor's half. Alt+Shift+arrows is dwindle's movewindow: remove
  the tile, re-insert as if the cursor were 2 px past its edge. Ctrl+Alt+arrows
  resizes by 40 px through the nearest split running that way.
- Empty workspace = an unused new-tab page (not pinned, not split, nothing
  loading, no history). Leaving one closes it (`skipSessionStore`), so `Alt+N`
  always lands on the single empty one. `about:blank` is deliberately not
  "empty" (pages opened by scripts start there).
- Alt+1…0 and the picker follow tab-list order (`gBrowser.visibleTabs`, splits
  counted once, collapsed folders skipped). Ctrl+Tab walks the current split's
  tiles in layout (reading) order.
- Start-up: user.js sets `zen.workspaces.continue-where-left-off` and
  `zen.urlbar.open-on-startup = false`; as a fallback the script watches the
  first 6 s (until a key or click) and, if Zen settles on a new-tab page, selects
  the most recently used workspace (`tab.lastAccessed`) and drops the unused
  start-up new tabs.
- Closing a tile selects the last-used tile of the same workspace: Firefox
  picks the next tab in `gBrowser._findTabToBlurTo()` before TabClose even
  fires (Zen's pick = most recently used tab anywhere), so the script wraps
  that method for tabs inside a split. Lone tabs keep Zen's pick.
- Closing the very last tab: `gBrowser.removeTab` is wrapped so the window
  closes at once, without removing the tab first (that made Zen show its empty
  "new tab" while the window went). For a fresh next start the script sets
  `browser.startup.page = 1` + `rice.tiles.fresh-start`, and the next window
  clears both (back to Zen's restore). Normal quits still restore.
- Tile animations copy Hyprland's: the `animations {}` block of
  `~/.config/hypr/hyprland.conf` is parsed at window start (beziers, speeds ×100 ms,
  `popin N%`, `enabled`). A MutationObserver on `#tabbrowser-tabpanels` sees every
  layout change (Zen's or ours); tiles that moved get a FLIP transform with
  `windows`, new ones `windowsIn` + `fadeIn`. Closing a tile with an animated close
  (Ctrl+W, ×, middle click) snapshots it first (≤90 ms) and plays `windowsOut` +
  `fadeOut` on the still. A change where no tile stays is a workspace switch:
  its tiles fade in with `workspacesIn`; switches the script makes (Alt+1…0,
  Alt+N, swipe, picker) first snapshot the old tiles (≤50 ms) and fade those out
  on top with `workspacesOut` — Hyprland's crossfade. Tab-list clicks: fade-in only. Zen's own 90 ms `inset` transition is switched off. Edit
  hyprland.conf's animations → restart Zen.
- Alt+Shift+N past the last workspace = a new workspace at the bottom
  (`toBottom`), the desktop's stacked numbering.
- Alt+drag (split view only; lone tabs keep Alt+click = Glance): chrome
  capture `mousedown` with Alt (or Alt tracked from keydown — headless/touchpad
  mouse events can lack the modifier) is eaten before the page sees it; a
  transparent popover takes the drag, the tile follows by transform, and the
  drop re-inserts it like dwindle's movewindow (`rectsWithout` = the layout
  without the dragged tile). Window `deactivate`, not `blur`, cancels — focus
  moving into a page fires `blur` on the window.
- Link tabs: `TabOpen` with `tab.openerTab` (set for links / window.open /
  middle click) → tiled next to the opener unless its split is full; not for
  pinned/Essential openers or Glance. The script's own new tabs are excluded
  (`ownTabs`).
- Zen's split limit (`MAX_TABS`, 4) is raised to 8.
- The picker is a `popover` (top layer) in the chrome document, styled with
  `--rice-*` like the rest; thumbnails from `drawSnapshot()`.
- Hyprland: a plain 3-finger swipe down/up runs `hypr/zen-swipe.sh up|down`
  (natural-scrolling style: swipe down = up the list),
  which sends Alt+PgUp/PgDn to Zen when it is the focused window. Not cyclic:
  swipe down on the top workspace opens a new tab (moved above the other unpinned
  tabs), swipe up on the bottom one does nothing.
- Focus follows the mouse between tiles of a split: the chrome `mousemove`
  target is the tile's `.browserSidebarContainer`/`<browser>`; skipped while a
  button is held, the picker is open, or you are actually typing in chrome UI
  (URL bar with typed text / open results, or a text-editing key — not a
  shortcut or bare modifier — pressed in a chrome input in the last 2.5 s). A caret merely sitting in the URL bar no longer blocks it —
  that is how Zen often starts, and hover did nothing until the first click.
  Position fallback when something overlays the page.

Testing: a scratch profile, `MOZ_REMOTE_ALLOW_SYSTEM_ACCESS=1 zen --headless
--marionette` and chrome-context scripts; keys through `nsITextInputProcessor`
take the real key path. `window.riceTiles` exposes the functions. Headless
content doesn't paint, so thumbnails only show in a real window.
