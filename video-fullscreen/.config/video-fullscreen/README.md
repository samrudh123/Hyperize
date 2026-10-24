# Video fullscreen (Firefox + Brave)

Fullscreen windows keep their transparency (opacity-rules.conf), but a
**video** put fullscreen with the player's own button should be solid. Hyprland
can't tell that apart from F11 / SUPER+F — the browser sends the same
fullscreen request — so this extension tells it.

| Piece | File |
|---|---|
| Every frame: is what's fullscreen a video (a `<video>`, or an element holding one that covers ≥ 40 % of the screen)? | `content.js` |
| Forwards each change to the native host | `background.js` |
| Native host: tags the browser's fullscreen window `vidfs` (and a detached follower drops the tag when it leaves fullscreen) | `~/.config/hypr/video-fullscreen.py` |
| Rule `video-fullscreen-opaque` (tag `vidfs` + fullscreen state 2 → opacity 1) | `~/.config/hypr/hyprland.conf` |

YouTube Music (the th-ch app) needs no extension: `video-fullscreen.py ytm`
(exec-once) follows its MPRIS `Fullscreen` property, which is the player's
fullscreen button.

`sh build.sh` builds `video-fullscreen.xpi` (Firefox, MV2) and `chromium/`
(Brave, MV3 — `key` pins the ID `adadbcfmpdifbfgbkbfaiaiphnfmkpip`) and
registers the native host for Firefox and every Chromium-family profile dir
that exists.

## Install
**Firefox** (release Firefox needs it signed):
1. https://addons.mozilla.org/developers/addon/submit/distribution → **On your own** (unlisted).
2. Upload `video-fullscreen.xpi`, wait for the automatic signing, download the signed `.xpi`.
3. `about:addons` → gear → *Install Add-on From File…* → the signed file.
4. Optional: allow it in private windows.

**Brave**: `brave://extensions` → *Developer mode* on → *Load unpacked* →
`~/.config/video-fullscreen/chromium`. Stays installed across restarts.

If you edit the extension: bump `version` in both manifests, `sh build.sh`,
re-sign for Firefox, press the reload arrow on the Brave card.

## Testing
`VIDEO_FS_LOG=/some/file` in the browser's environment makes the host log each
message. `video-fullscreen.py tag PID` / `untag PID` drive the tag by hand.
Tested headless (Firefox Marionette with a temporary install; Brave
`--headless=new --load-extension` + CDP at a 1920×1200 viewport): a player
`<div>` with a video, a bare `<video>`, and a cross-origin iframe player
(Firefox) send `true`/`false`; the whole page put fullscreen with a small
video on it sends nothing.
