# Video fullscreen (Firefox + Brave)

Fullscreen windows keep their transparency (opacity-rules.conf), but a
**video** put fullscreen with the player's own button should be solid. Hyprland
can't tell that apart from F11 / SUPER+F — the browser sends the same
fullscreen request — so this extension tells it.

| Piece | File |
|---|---|
| Top frame: "something in this tab went in/out of DOM fullscreen" (F11 / SUPER+F never fire it) | `content.js` |
| Looks into **every** frame (cross-origin too): is the fullscreen element a big `<video>` / holds one, or holds a big frame while some frame shows a big `<video>`? Tells the native host | `background.js` |
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

1.1.0 (2026-10-26) — 1.0.0 decided per frame, so it missed players whose
page fullscreens the `<iframe>` (or a box around it): inside the player's
frame nothing is fullscreen, and up top the fullscreen element holds no
`<video>`. Tested headless, Firefox (Marionette, temporary install) and Brave
(`--headless=new --load-extension` + CDP, 1920×1200 viewport):
player `<div>`, bare `<video>`, iframe player fullscreening its own box or
its `<html>`, nested iframes, the page fullscreening the iframe or a wrapper
around it → `true`; a page put fullscreen with a small clip on it, a
fullscreened non-video box → nothing. Real sites: AnimeSuge (Plyr in
my.1anime.site), AnimeKai (JW Player in megaplay.buzz), HiAnime (JW Player in
zokoanime.video). Headless fullscreen is 1366×768 in Firefox and 800×544 in
Brave unless overridden — the 20 %-of-screen size test reads differently there.
