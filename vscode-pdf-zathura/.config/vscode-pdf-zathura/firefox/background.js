// PDF in Zathura for Firefox: every PDF Firefox would show in its own viewer
// is sent to viewer.html instead, which runs media/viewer.js, the same
// zathura-style viewer as the VS Code extension. The native host (host.py)
// sends the parsed zathurarc, and again whenever set-accent.sh rewrites it.
//
// Attachments ("download this") are previewed too, not just inline PDFs:
// nothing lands on disk until Ctrl+S in the viewer hands it to dl-popup.
// dl-popup's own "Preview in zathura" (for PDFs that only ever show up as
// downloads) comes in through onMessageExternal.
//
// Page action (URL bar): open the current PDF in Firefox's own viewer, for
// forms and the like.

const HOST = "pdf_zathura";
const VIEWER = browser.runtime.getURL("viewer.html");
const DL_POPUP = "dl-popup@samrudh.local";
const PDF = /^\s*application\/(x-)?pdf\s*(;|$)/i;
// Generic "binary" types some servers send PDFs as; then the name has to say .pdf.
const BINARY = /^\s*(application\/(octet-stream|x-download|force-download|download|binary)|binary\/octet-stream)\s*(;|$)/i;
const bypass = new Map();   // url -> expiry: loads deliberately left to Firefox
const opened = new Set();   // ids of the viewers this redirected to

const viewers = new Set();  // ports of open viewer.html pages
let native = null;
let rc = null;              // last zathurarc from the host

function send(port) {
  port.postMessage({ type: "config", rc: rc ?? { options: {}, maps: [] } });
}

function connectHost() {
  if (native) return;
  native = browser.runtime.connectNative(HOST);
  native.onMessage.addListener((msg) => {
    if (msg.type !== "config") return;
    rc = msg.rc;
    viewers.forEach(send);
  });
  native.onDisconnect.addListener((p) => {
    if (p.error) console.error("pdf-zathura: native host", p.error);
    // No host (not installed, or it died): viewers fall back to zathura's
    // defaults rather than waiting.
    if (native === p && !rc) viewers.forEach(send);
    if (native === p) native = null;
  });
}

function header(details, name) {
  return details.responseHeaders.find((h) => h.name.toLowerCase() === name)?.value ?? "";
}

// RFC 6266 filename*=UTF-8''… first, then plain filename="…".
function dispositionName(cd) {
  const ext = /filename\*\s*=\s*[^']*'[^']*'([^;]+)/i.exec(cd);
  if (ext) {
    try { return decodeURIComponent(ext[1].trim()); } catch {}
  }
  return /filename\s*=\s*"?([^";]+)"?/i.exec(cd)?.[1].trim() ?? "";
}

function urlName(url) {
  try { return decodeURIComponent(new URL(url).pathname.split("/").pop()); } catch { return ""; }
}

// A viewer may fetch only what this file sent it to (see shim.js ready()).
function viewerUrl(file, name, attachment) {
  const id = crypto.randomUUID();
  opened.add(id);
  const q = new URLSearchParams({ file, id });
  if (name) q.set("name", name);
  if (attachment) q.set("attachment", "1");
  return `${VIEWER}?${q}`;
}

// A PDF link clicked on a web page opens the viewer in a new tab next to it,
// and the page stays. Typed URLs, fresh tabs (target=_blank, middle click),
// frames and private windows load the viewer in place.
async function besideOrInPlace(d, url) {
  const tab = await browser.tabs.get(d.tabId).catch(() => null);
  if (!tab || tab.incognito || !/^https?:/i.test(tab.url ?? "")) return { redirectUrl: url };
  browser.tabs.create({
    url, windowId: tab.windowId, index: tab.index + 1, openerTabId: tab.id, cookieStoreId: tab.cookieStoreId,
  });
  return { cancel: true };
}

function leaveToFirefox(url) {
  bypass.set(url, Date.now() + 30000);
}

browser.webRequest.onHeadersReceived.addListener(
  (d) => {
    if (d.method !== "GET" || d.tabId < 0 || d.statusCode < 200 || d.statusCode >= 300) return;
    const until = bypass.get(d.url);
    if (until !== undefined) {
      bypass.delete(d.url);
      if (until > Date.now()) return;
    }
    const type = header(d, "content-type");
    const cd = header(d, "content-disposition");
    const name = dispositionName(cd);
    if (!PDF.test(type) && !(BINARY.test(type) && /\.pdf$/i.test(name || urlName(d.url)))) return;
    // Attachments would have been downloads: previewed all the same, but if
    // they can't be fetched again the viewer says so instead of handing the
    // URL back to Firefox (which would just download it).
    const url = viewerUrl(d.url, name, /^\s*attachment/i.test(cd));
    if (d.type === "main_frame" && /^https?:/i.test(d.originUrl ?? "")) return besideOrInPlace(d, url);
    return { redirectUrl: url };
  },
  { urls: ["http://*/*", "https://*/*"], types: ["main_frame", "sub_frame"] },
  ["blocking", "responseHeaders"],
);

browser.runtime.onConnect.addListener((port) => {
  if (port.name !== "viewer") return;
  viewers.add(port);
  const tab = port.sender.tab;
  if (tab && port.sender.frameId === 0) browser.pageAction.show(tab.id);
  if (rc) send(port);
  connectHost();
  port.onDisconnect.addListener(() => {
    viewers.delete(port);
    // The host only runs while a viewer is open; the next one starts it
    // again and gets a fresh read.
    if (!viewers.size && native) {
      native.disconnect();
      native = null;
      rc = null;
    }
  });
});

browser.runtime.onMessage.addListener(async (msg) => {
  if (msg.type === "opened") {
    return opened.has(msg.id);
  } else if (msg.type === "firefox") {
    leaveToFirefox(msg.url);
  } else if (msg.type === "save") {
    // Through Firefox's downloads, so dl-popup sees it like any other.
    const opts = { url: msg.url };
    const name = (msg.name || "").replace(/[\\/:*?"<>|\x00-\x1f]/g, "_").trim();
    if (name) opts.filename = name;
    await browser.downloads.download(opts);
  } else if (msg.type === "fetch") {
    // for viewers in frames, see shim.js get()
    const res = await fetch(msg.url, msg.init);
    return { status: res.status, type: res.headers.get("content-type") ?? "", data: await res.arrayBuffer() };
  }
});

// dl-popup's "Preview in zathura": a PDF that reached Firefox's downloads
// (download links, Save Link As, ...). Opens next to the current tab.
browser.runtime.onMessageExternal.addListener(async (msg, sender) => {
  if (sender.id !== DL_POPUP || msg?.type !== "preview" || !/^https?:\/\//i.test(msg.url ?? "")) return;
  const [cur] = await browser.tabs.query({ active: true, currentWindow: true });
  const opts = { url: viewerUrl(msg.url, msg.name, true) };
  if (cur && !cur.incognito) Object.assign(opts, { index: cur.index + 1, openerTabId: cur.id });
  if (msg.cookieStoreId) opts.cookieStoreId = msg.cookieStoreId;
  await browser.tabs.create(opts);
  return true;
});

browser.pageAction.onClicked.addListener((tab) => {
  if (!tab.url?.startsWith(VIEWER)) return;
  const file = new URL(tab.url).searchParams.get("file");
  if (!file) return;
  leaveToFirefox(file);
  browser.tabs.update(tab.id, { url: file });
});
