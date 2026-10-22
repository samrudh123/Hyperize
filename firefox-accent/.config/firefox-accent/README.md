# Rice Accent, for Firefox

Firefox's toolbar, tabs, menus and sidebar follow the desktop theme and
accent **live**: SUPER+ALT+C (accent) and SUPER+SHIFT+T (theme) recolour every
open Firefox window without a restart.

| Piece | File |
|---|---|
| Native host: watches `~/.config/hypr/theme/{palette.json,accent}`, sends changes | `host.py`, registered in `~/.mozilla/native-messaging-hosts/rice_accent.json` |
| Turns each message into `browser.theme.update()` | `background.js` |

`sh build.sh` packs `rice-accent.xpi` and (re)writes the native host manifest.

## How it fits with userChrome.css
`userChrome.css` (a `set-accent.sh` template) paints the chrome from its
`--ctp-*` variables. Under `:root[lwtheme]` — i.e. while a Firefox theme is
applied — those variables are read from the CSS variables Firefox sets for
the theme (`--toolbarbutton-icon-fill-attention` carries the accent,
`--lwt-accent-color` crust, `--toolbar-background-color` mantle, …; the full
mapping is the comment in `background.js` → `themeFor` and the `:root[lwtheme]`
block in userChrome.css). Without the extension Firefox's default theme is
active, `[lwtheme]` doesn't match, and the hex values set-accent.sh rendered
are used — the old behaviour, a restart picks up a change.

`userContent.css` (about: pages, the new tab page's styling beyond its
background) is still read only at startup.

## Install (release Firefox needs it signed)
1. https://addons.mozilla.org/developers/addon/submit/distribution → **On your own** (unlisted).
   (If the upload fails with "empty response, status: 0", use a private window.)
2. Upload `rice-accent.xpi`, wait for the automatic signing, download the signed `.xpi`.
3. Firefox → `about:addons` → gear → *Install Add-on From File…* → pick the signed file.
4. Allow it in private windows too if you want them themed (about:addons → Rice Accent).

Quick test without signing: `about:debugging#/runtime/this-firefox` →
*Load Temporary Add-on…* → `rice-accent.xpi` (gone after restart).

If you edit the extension, bump `version` in manifest.json, rebuild, re-sign.

Tested headless (Marionette, temporary install, fake HOME): accent file
change → `--ctp-accent` and everything derived from it updated in ~1 s;
palette.json replaced → `--ctp-base` updated; extension removed → back to the
rendered hex.
