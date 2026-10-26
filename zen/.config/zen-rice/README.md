# Zen: live desktop theme + accent

Firefox follows SUPER+ALT+C (accent) and SUPER+SHIFT+T (theme) live through
the Rice Accent extension and Firefox's theme API. Zen ignores Firefox themes,
and its own live accent is a pref (`zen.theme.accent-color`) nothing outside
the browser can set. So Zen gets an **autoconfig** script instead: privileged
JavaScript Zen runs from its install directory at every start.

| File | Goes to | Does |
|---|---|---|
| `autoconfig.js` | `~/.local/opt/zen/defaults/pref/` | tells Zen to run `rice-live.cfg` (unsandboxed) |
| `rice-live.cfg` | `~/.local/opt/zen/` | once a second, stats `~/.config/hypr/theme/accent` and `palette.json`; on change sets `--rice-accent`, `--rice-base`, … on every Zen window and its bookmarks/history sidebar, and registers a small user sheet with the same variables for Zen's own pages (new tab, settings, about:), which run in content processes |

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
