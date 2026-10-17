# dl-popup — IDM-style download popup for Firefox → aria2 / JDownloader

Click a download in Firefox → the extension cancels it → native host →
`~/.local/bin/dl-popup add` shows a fuzzel menu (folder, filename, speed,
chunks, parallel, backend) → queued in aria2 (default) or JDownloader.
Picking "Let Firefox download it", or any failure, gives the download back to Firefox.

PDFs get "Preview in zathura (nothing saved)" as the first row (Enter = preview):
it opens the PDF in the PDF in Zathura extension (`~/.config/vscode-pdf-zathura/firefox`)
instead of saving. Not offered for saves made from that viewer (Ctrl+S / `save`),
nor in private windows. If that extension isn't installed, the popup comes back
without the row. Most PDF links never get here: that extension previews them
(attachments included) before Firefox treats them as downloads.

| Piece | Path |
|---|---|
| Popup / queue menu | `~/.local/bin/dl-popup` (`add`, `status`, `jd`) |
| Defaults | `~/.config/dl-popup/config.json` |
| aria2 daemon | `~/.config/aria2/aria2.conf`, `~/.config/systemd/user/aria2.service` |
| Notifications | `~/.config/aria2/on-complete.sh`, `on-error.sh` |
| Firefox extension | `firefox-extension/` (source), `dl-popup.xpi` (unsigned build, gitignored) |
| Native host | `native-host.py`, registered in `~/.mozilla/native-messaging-hosts/dl_popup.json` |
| Build | `sh build.sh` packs `dl-popup.xpi` and (re)writes that native host manifest |
| Queue menu key | `SUPER + ALT + D` (hyprland.conf) |

## Install the extension permanently (release Firefox needs it signed)
1. https://addons.mozilla.org/developers/addon/submit/distribution → **On your own** (unlisted).
2. Upload `dl-popup.xpi`, wait for the automatic signing, download the signed `.xpi`.
3. Firefox → `about:addons` → gear → *Install Add-on From File…* → pick the signed file.

Quick test without signing: `about:debugging#/runtime/this-firefox` →
*Load Temporary Add-on…* → `firefox-extension/manifest.json` (gone after restart).

If you edit the extension, bump `version` in manifest.json, run `sh build.sh`, re-sign.
Upload from a **private window**: in a normal one an add-on breaks AMO's uploader
("Received an empty response from the server; status: 0").

## Firefox settings that matter
- Settings → Downloads: turn **off** "Always ask you where to save files"
  (otherwise Firefox's own dialog appears before the popup).
- `about:config` → `browser.download.alwaysOpenPanel` = false (no panel flash).

## Fuzzel keys
Enter picks. To type a value that isn't in the list (custom path, `750K`, `12`),
type it and press **Shift+Enter**.

Folder "Browse…" in the popup opens yazi: `q` = use this folder, Space+Enter = use the marked folder, `Q` = cancel.

## Default folder
The popup starts in the folder you used last (`recent_dirs[0]` in config.json);
`default_dir` only applies until a folder has been picked once.

## Terminal downloads → JDownloader
`~/.config/dl-popup/terminal.zsh` (sourced from ~/.zshrc) wraps `curl` and `wget`
in interactive zsh only. Plain file downloads (`curl -O/-LO/-o FILE URL`,
`wget URL`, `wget -O FILE URL`, `-P DIR`) run through `dl-popup fetch`: JD
downloads into a hidden `.jd-fetch-PID` folder next to the target, the command
waits and prints progress, then the file is moved into place and the JD entry
removed. Archives are not auto-extracted.

Everything else runs the real tool: API calls, `curl … | sh`, headers/POST/auth,
several URLs, links JD drops (e.g. one already in its list), or JD failing.
Scripts, Makefiles and Dockerfiles are never redirected — they use /usr/bin/curl
— but their curl/wget show up in the bar (bytes + speed; size is unknown).

Package managers (`uv add/sync/lock/pip …`, `pip install/download/wheel`,
`conda`/`mamba`/`micromamba install/create/update/env …`) also show in the bar
while they are writing: 󰏔 + command + bytes written + speed. That counts cache
writes and unpacking, so it means "busy, this fast", not an exact download size.
They drop off after 6 s without writing; `uv run` and other commands never show.

Bypass once: `command curl …`   Off for a shell: `export DL_POPUP_FETCH=0`
