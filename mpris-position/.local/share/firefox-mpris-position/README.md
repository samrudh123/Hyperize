# firefox-mpris-position — YouTube tabs as MPRIS players for the bottom bar

Two jobs, one extension (id `mpris-position@samrudh.local`):

1. **One MPRIS player per YouTube tab** (1.1.0). Firefox publishes a single
   MPRIS player for whichever tab it last started, so with two YouTube tabs
   playing the bar showed one and the other was unreachable. Now every tab
   with a YouTube / YouTube Music player is its own player,
   `firefox.tab_<tabId>` (playerctl -l shows them all):
   - the bar's laptop pill shows the tab you're ON (the focused Firefox
     window's active tab if it has a player, else the last such tab you were
     on) — `$XDG_RUNTIME_DIR/firefox-tabs.current`, read by now-playing.py;
   - the media menu (media-menu.py) lists every tab ("YouTube · tab",
     "· this tab"); picking one switches Firefox to that tab and focuses its
     window, so it becomes the one in the bar;
   - play/pause/seek/next/prev from the bar or playerctl go to that tab.
   Firefox's own player is hidden from the bar/menu while it is one of
   these YouTube tabs.
3. **Shuffle / repeat** (1.2.0) for the bar's ⇄ ⟲ buttons: each tab player
   has MPRIS `Shuffle` / `LoopStatus` where the page has them, and setting
   them clicks YouTube's own buttons (tab.js `modes()` / `setLoop()` /
   `setShuffle()`), so the page and the bar agree:
   - YouTube playlist (`&list=`): the playlist panel's loop button — off →
     loop playlist → loop video (`None` / `Playlist` / `Track`), state read
     language-independently from the renderer's `data.states` — and its
     shuffle toggle;
   - a single YouTube video: `<video loop>` (= right-click "Loop"): repeat
     only, off ↔ this video; no shuffle button;
   - YouTube Music: the player bar's `repeatMode` (NONE / ALL / ONE) and
     `shuffleOn`. Its shuffle starts a new song; the tab's player now stays
     up while the next track loads (it used to vanish for ~1 s).
   Changes made on the page itself are re-reported after any click.
   Verified in a headless Firefox 2026-10-26 (all three, both directions).
2. **Reliable length/position for Firefox's own player** (1.0.0,
   `position.js`). YouTube reports them to Firefox unreliably (title but no
   length, position stuck near 0 → no progress line); this reports them from
   the playing `<video>` and ignores YouTube's own calls.

| Piece | Path |
|---|---|
| Extension source | `extension/` — `manifest.json` (MV3), `position.js` (page world), `tab.js` (per tab), `background.js` |
| Build | `build.sh` → `firefox-mpris-position.xpi` (unsigned), installed into Zen; also registers the native host |
| Native host | `host.py`, registered in `~/.mozilla/native-messaging-hosts/firefox_tabs.json` |
| Host log | `~/.local/state/firefox-tabs/host.log` (`FIREFOX_TABS_DEBUG=1` in Firefox's environment logs every message) |

Nothing leaves the machine: tab titles/URLs/positions go only to `host.py`
over native messaging, which publishes them on the session D-Bus.

## Install / update (release Firefox needs it signed, same as dl-popup)
1. `./build.sh`, then https://addons.mozilla.org/developers/addon/submit/distribution → **On your own** (unlisted).
   For an update: the add-on's page → *Upload a New Version*.
2. Upload `firefox-mpris-position.xpi`, wait for the automatic signing, download the signed `.xpi`.
3. Firefox → `about:addons` → gear → *Install Add-on From File…* → pick the signed file.
   1.1.0 asks for two new permissions (tabs, native messaging) — accept.
   1.2.0 (shuffle / repeat) needs no new permissions; restart the browser so
   the new `host.py` is used.

Zen (the browser now) takes the unsigned build as it is — no signing:
`./build.sh` installs it (`install.sh copy` runs it once), then restart Zen.

Quick test without signing: `about:debugging#/runtime/this-firefox` →
*Load Temporary Add-on…* → `extension/manifest.json` (gone after restart).

Is it running? `playerctl -l` shows `firefox.tab_<n>` for each YouTube tab
that has played; `pgrep -f firefox-mpris-position/host.py`. On a YouTube
page, devtools → `<html data-mpris-position="1">` (position.js).

If you edit it: bump `version` in manifest.json and re-run `./build.sh`
(re-sign on AMO only for Firefox).
(`host.py` is not in the xpi — edits to it apply when the browser restarts.)

## Notes
- Why not Enhancer for YouTube's "Custom script": Enhancer injects it as an
  inline `<script>`, and YouTube's Content-Security-Policy blocks it (checked
  in Firefox 156).
- Firefox 156 keeps advancing its own MPRIS `Position` while a video is
  PAUSED. position.js reports a near-zero rate (1e-6) while paused, and
  now-playing.py holds a paused Firefox player's position.
- Switching tabs: Firefox can't raise its own window on Wayland, so host.py
  finds the window by the tab's title in `hyprctl clients` and focuses it
  (only guesses a window when there's just one Firefox window).
- Tested with a headless Firefox: two tabs → two players, current follows
  the active tab and Raise(), play/pause/seek/next/⏮ restart. Seeking a
  PAUSED video in a background tab stalled there (headless doesn't load
  video for hidden tabs); host.py then holds the clock instead of guessing.
