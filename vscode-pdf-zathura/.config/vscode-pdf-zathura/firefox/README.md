# PDF in Zathura, for Firefox

PDFs that Firefox would open in its own viewer (pdf.js with the edit
toolbar), and PDFs sent as downloads (`Content-Disposition: attachment`, or
`application/octet-stream` named `*.pdf`), open in the zathura-style viewer
instead, so nothing lands on disk until you save it: the same `media/viewer.js`
the VS Code extension uses, so the same keys, statusbar, index, search,
link hints and recolour, themed from `~/.config/zathura/zathurarc` and
re-themed live when `set-accent.sh` rewrites it.

| Piece | File |
|---|---|
| Redirects PDF loads, native port, downloads | `background.js` |
| The viewer page | `viewer.html` (+ `../media`, copied in by `build.sh`) |
| Stand-in for the VS Code webview API | `shim.js` |
| Native host: parses zathurarc, sends changes | `host.py`, registered in `~/.mozilla/native-messaging-hosts/pdf_zathura.json` |

`sh build.sh` packs `pdf-zathura.xpi` and (re)writes the native host manifest.

## Install (release Firefox needs it signed)
1. https://addons.mozilla.org/developers/addon/submit/distribution → **On your own** (unlisted).
2. Upload `pdf-zathura.xpi`, wait for the automatic signing, download the signed `.xpi`.
3. Firefox → `about:addons` → gear → *Install Add-on From File…* → pick the signed file.

Quick test without signing: `about:debugging#/runtime/this-firefox` →
*Load Temporary Add-on…* → `pdf-zathura.xpi` (gone after restart).

If you edit the extension or `../media`, bump `version` in manifest.json,
rebuild, re-sign.

## Which tab
A PDF link clicked on a web page opens the viewer in a new tab next to it;
the page stays where it was. Typed URLs, links that open a new tab anyway
(`target=_blank`, middle click), PDFs in frames (IEEE's stamp page) and
private windows load the viewer in place.

## Besides zathura's keys
- `Ctrl+S`, or `save` in the statusbar, saves the PDF through Firefox's
  downloads, so dl-popup catches it (without its Preview row: you've seen it).
- dl-popup's "Preview in zathura" row (PDFs that only show up as downloads:
  Save Link As, pdf.js's download button...) opens the viewer in a new tab
  via `onMessageExternal`, accepted from `dl-popup@samrudh.local` only.
- `q` closes the tab; links open in a new tab next to it.
- The page-action icon in the URL bar reopens the PDF in Firefox's own
  viewer (forms, annotations).

## What it leaves to Firefox
- POST results, `file://` PDFs, PDFs in `<embed>`/`<object>`.
- The PDF is downloaded once: the page load's own response is read as it
  arrives (`filterResponseData`) and handed to the viewer, so bot walls
  (Cloudflare on dl.acm.org refused any second download) and one-time links
  work. Fetching again is only the fallback (a reload, dl-popup's Preview),
  sent with headers that match a click.
- Inline PDFs it can't fetch again (expired one-time links, login
  redirects): it falls back to Firefox's viewer for that load. An
  attachment that fails (or a `*.pdf` that isn't one) shows an error in the
  viewer instead, since Firefox would only download it; `Ctrl+S` still hands
  it to dl-popup.
