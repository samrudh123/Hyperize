# firefox-media-title-sync — right episode title in the media notification

1.1.0: works on any streaming site of this kind, not just AnimeKai (AnimeSuge
had the same problem). Update the phone the same way as the first install
(sign the new xpi as a new version of the same add-on, install from file).

Made for Firefox on an Android phone, whose media notification KDE Connect
mirrors to the laptop. Also works in desktop Firefox and Zen. The id is
`media-title-sync@samrudh.local`.

**Problem:** on AnimeKai the phone's media notification said "Episode 8" while
episode 9 was playing. KDE Connect passed that title on to the laptop's
playerctl and bar. There are two causes, and both were confirmed in a
headless Firefox 156:
1. AnimeKai changes episodes without loading a new page (history.pushState)
   and never updates `document.title`. The tab itself still said "Episode 8".
2. The video plays in an iframe (megaplay.buzz, JW Player). The player sets
   `navigator.mediaSession.metadata` with an EMPTY title and artist
   "megaplay.buzz", so Firefox fills the title in from the page title. It
   does this only when the metadata is set, not on later page-title changes
   (`MediaStatusManager::NotifyPageTitleChanged` skips sessions that have
   metadata). Changing the top page's title fired no `metadatachange`.

**Fix:**
- `top.js` (top page, any site), once the page plays media: when the address
  changes and the site hasn't updated `document.title` 1.5 s later, fetch the
  new address (as the page — `content.fetch`, its cookies) and use the
  `<title>` the site serves for it. At most one fetch per 5 s, cached per
  address; interstitial titles ("Just a moment…" etc.) are ignored. Pages
  without media are never watched, and nothing is fetched while the site
  keeps its own title current (YouTube etc.).
- `animekai.js` (top page, AnimeKai domains): copies the episode from the URL
  (`/watch/<anime>/ep-9`) into the title's last "Episode N" at once, without
  the fetch.
- `frame.js` (page world, every iframe on every site): when a player sets
  metadata with no title, it tells the top page. When the top page asks, it
  sets the same metadata again, and Firefox then reads the page title afresh.
- `top.js` also tells such frames to set their metadata again whenever the
  title changes (checked every 0.5 s).

No extension APIs and nothing sent anywhere new: the only network request is
the page's own site, for the address you're already on.

| Piece | Path |
|---|---|
| Source | `extension/` (`manifest.json` MV3, needs Firefox ≥ 128 for page-world scripts) |
| Build | `build.sh` → `firefox-media-title-sync.xpi` (unsigned), installed into Zen |

`install.sh` doesn't install this one (it's for the phone); run `build.sh`
yourself if you want it in Zen.

## Install on the phone (release Firefox needs it signed)
1. `./build.sh`, then
   https://addons.mozilla.org/developers/addon/submit/distribution →
   **On your own** (unlisted) → upload `firefox-media-title-sync.xpi`, wait for
   signing, download the signed `.xpi`.
2. Send it to the phone, e.g.
   `kdeconnect-cli -n "<phone name>" --share ~/Downloads/<signed>.xpi`
   (`kdeconnect-cli -l` lists the names).
3. Firefox on the phone → Settings → About Firefox → tap the Firefox logo 5×
   ("debug menu enabled") → back to Settings → **Install extension from file**
   → pick the signed file.
4. Settings → Extensions → Media Title Sync → Permissions → make sure
   access to all websites is ON (needed for the player iframes, whose hosts
   vary by server).

Desktop: `./build.sh` installs it into Zen unsigned (loads when Zen next
starts). Firefox: `about:addons` → gear → *Install Add-on From File…* → the
signed file. To test it quickly without signing, use `about:debugging` →
*Load Temporary Add-on…* → `extension/manifest.json`.

If you edit it, bump `version` in `manifest.json` and re-run `./build.sh`
(the phone's Firefox still needs the AMO-signed file).

## Tested (headless Firefox 156, Marionette, audio to a null sink)
1.1.0: AnimeSuge ep 2 → 3 (stale "Episode 2" before): title + metadata
"Episode 3" ~3 s after the click, metadatachange fired. AnimeKai 8 → 9 still
right, also with `animekai.js` removed (the generic fetch alone).

1.0.0:
Watched `mediaController.getMetadata()` and `metadatachange` events in chrome:
- Before the fix, ep 8 → click ep 9: the tab title stayed "Episode 8", and so
  did the metadata.
- With the extension, ep 8 → 9 → 10 by clicking: the title and the media
  metadata updated within about 1.5 s, and a metadatachange fired each time.
  Playback was not interrupted.
- When the title changes AFTER the player has set its metadata, the request
  from `top.js` brings the metadata up to date within about 1 s and fires the
  event.
- Not tested on Android itself. The Android app uses the same Gecko code,
  and the phone's notification listens to the same event.
