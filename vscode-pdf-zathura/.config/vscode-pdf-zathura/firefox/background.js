// PDF in Zathura for Firefox: every PDF Firefox would show in its own viewer
// is sent to viewer.html instead, which runs media/viewer.js, the same
// zathura-style viewer as the VS Code extension. The native host (host.py)
// sends the parsed zathurarc, and again whenever set-accent.sh rewrites it.
//
// The PDF is not downloaded twice: the page load's own response is read as
// it arrives (filterResponseData), kept here, and replaced by a stub page
// that moves on to the viewer, which asks for the kept bytes. A second
// download (a fetch from the viewer) is what bot walls refuse — Cloudflare
// on dl.acm.org gave it 403 + a challenge while the click had the PDF — and
// what one-time links can't serve. It is only the fallback now (reload, and
// dl-popup's Preview, which has no page load to read).
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
// PDFs a viewer is about to fetch again -> {referrer, until}. Its fetch is
// rewritten to look like the page load it replaces (see onBeforeSendHeaders).
const refetch = new Map();
const refetchIds = new Set();  // their request ids, so redirects keep the headers

function viewerUrl(file, name, attachment, referrer = "", captured = false) {
  const id = crypto.randomUUID();
  opened.add(id);
  const now = Date.now();
  for (const [u, r] of refetch) if (r.until < now) refetch.delete(u);
  refetch.set(file, { referrer, until: now + 10 * 60000 });
  const q = new URLSearchParams({ file, id });
  if (name) q.set("name", name);
  if (attachment) q.set("attachment", "1");
  if (captured) q.set("cap", "1");
  return { url: `${VIEWER}?${q}`, id };
}

// ── the page load's own bytes ───────────────────────────────────────────
const captured = new Map();     // viewer id -> {blob, until}
const KEEP_MS = 3 * 3600000;    // F5 in the viewer within this reuses them

function keep(id, blob) {
  const now = Date.now();
  for (const [k, v] of captured) if (v.until < now) captured.delete(k);
  while (captured.size >= 30) captured.delete(captured.keys().next().value);
  captured.set(id, { blob, until: now + KEEP_MS });
}

// What the tab (or frame) gets instead of the PDF: replaces itself with the
// viewer, so Back goes to the page before, not here.
function stub(viewer, name) {
  const esc = (t) => t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/"/g, "&quot;");
  return `<!DOCTYPE html><meta charset="utf-8"><title>${esc(name || "PDF")}</title>`
    + `<script>location.replace(${JSON.stringify(viewer).replace(/</g, "\\u003c")})</script>`
    + `<noscript><meta http-equiv="refresh" content="0; url=${esc(viewer)}"></noscript>`;
}

const DROP = new Set(["content-type", "content-disposition", "content-length", "content-security-policy",
                      "content-security-policy-report-only", "x-content-type-options", "cache-control",
                      "expires", "etag", "last-modified"]);

function capture(d, name, attachment) {
  const { url, id } = viewerUrl(d.url, name, attachment, d.originUrl ?? "", true);
  const filter = browser.webRequest.filterResponseData(d.requestId);
  const chunks = [];
  filter.ondata = (e) => chunks.push(e.data);
  filter.onstop = () => {
    keep(id, new Blob(chunks, { type: "application/pdf" }));
    filter.write(new TextEncoder().encode(stub(url, name)));
    filter.close();
  };
  filter.onerror = () => console.error("pdf-zathura: could not read", d.url, filter.error);
  // An HTML page now (no CSP, so the stub's one line of script runs), and
  // not cached: the cache must keep the PDF, not this.
  const h = d.responseHeaders.filter((x) => !DROP.has(x.name.toLowerCase()));
  h.push({ name: "Content-Type", value: "text/html; charset=utf-8" }, { name: "Cache-Control", value: "no-store" });
  return { responseHeaders: h };
}

// A PDF link clicked on a web page opens the viewer in a new tab next to it,
// and the page stays: this load is cancelled and the new tab loads the PDF
// itself (an ordinary navigation, so cookies and all), which comes back
// through here and is read in place. Typed URLs, fresh tabs (target=_blank,
// middle click), frames and private windows load the viewer in place.
const inPlaceOnce = new Map();  // url -> expiry: the new tab's load of it

async function besideOrInPlace(d, name, attachment) {
  const tab = await browser.tabs.get(d.tabId).catch(() => null);
  if (!tab || tab.incognito || !/^https?:/i.test(tab.url ?? "")) return capture(d, name, attachment);
  inPlaceOnce.set(d.url, Date.now() + 30000);
  browser.tabs.create({
    url: d.url, windowId: tab.windowId, index: tab.index + 1, openerTabId: tab.id, cookieStoreId: tab.cookieStoreId,
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
    // they can't be read the viewer says so instead of handing the URL back
    // to Firefox (which would just download it).
    const attachment = /^\s*attachment/i.test(cd);
    const once = inPlaceOnce.get(d.url);
    if (once !== undefined) inPlaceOnce.delete(d.url);
    if (d.type === "main_frame" && !(once > Date.now()) && /^https?:/i.test(d.originUrl ?? "")) {
      return besideOrInPlace(d, name, attachment);
    }
    return capture(d, name, attachment);
  },
  { urls: ["http://*/*", "https://*/*"], types: ["main_frame", "sub_frame"] },
  ["blocking", "responseHeaders"],
);

// When the viewer does fetch the PDF again (the fallback, see the top), a
// fetch says so: "Sec-Fetch-Mode: cors", "Sec-Fetch-Dest: empty", an
// Origin of moz-extension://. Bot walls take that for a script and refuse
// it: Cloudflare in front of dl.acm.org answers 403 + a challenge page where
// the click itself got the PDF, and the viewer fell back to Firefox's. So
// for exactly those fetches, send what the page load sent: a top-level,
// user-initiated navigation with the page it came from as Referer.
const BASE = browser.runtime.getURL("");
browser.webRequest.onBeforeSendHeaders.addListener(
  (d) => {
    if (!(d.originUrl ?? "").startsWith(BASE)) return;
    const r = refetch.get(d.url) ?? (refetchIds.has(d.requestId) ? { referrer: "" } : null);
    if (!r) return;
    refetchIds.add(d.requestId);
    const drop = new Set(["origin", "accept", "referer", "sec-fetch-dest", "sec-fetch-mode",
                          "sec-fetch-site", "sec-fetch-user", "upgrade-insecure-requests"]);
    const h = d.requestHeaders.filter((x) => !drop.has(x.name.toLowerCase()));
    let site = "none";
    if (r.referrer) {
      try { site = new URL(r.referrer).origin === new URL(d.url).origin ? "same-origin" : "cross-site"; } catch {}
      h.push({ name: "Referer", value: r.referrer });
    }
    h.push({ name: "Accept", value: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" },
           { name: "Upgrade-Insecure-Requests", value: "1" },
           { name: "Sec-Fetch-Dest", value: "document" },
           { name: "Sec-Fetch-Mode", value: "navigate" },
           { name: "Sec-Fetch-Site", value: site },
           { name: "Sec-Fetch-User", value: "?1" });
    return { requestHeaders: h };
  },
  { urls: ["http://*/*", "https://*/*"], types: ["xmlhttprequest"] },
  ["blocking", "requestHeaders"],
);
browser.webRequest.onCompleted.addListener((d) => refetchIds.delete(d.requestId), { urls: ["<all_urls>"] });
browser.webRequest.onErrorOccurred.addListener((d) => refetchIds.delete(d.requestId), { urls: ["<all_urls>"] });

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
  } else if (msg.type === "captured") {
    const c = captured.get(msg.id);
    return c ? c.blob.arrayBuffer() : null;
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
  const opts = { url: viewerUrl(msg.url, msg.name, true).url };
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
