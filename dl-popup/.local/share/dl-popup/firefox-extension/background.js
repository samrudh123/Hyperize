// dl-popup: every http(s)/ftp download Firefox starts is cancelled and handed
// to the native host (dl_popup → ~/.local/bin/dl-popup), which shows a fuzzel
// popup and queues it in aria2 or JDownloader. If the user picks "Let Firefox
// download it", or anything on the native side fails, the download is restarted
// in Firefox, so a click is never silently lost.
//
// PDFs get a "Preview in zathura" row first (unless the save came from that
// viewer): the PDF in Zathura extension opens it in a tab, nothing is saved.
//
// Toolbar button: pause / resume catching.  Link context menu: "Download with
// dl-popup" (works while paused too).

const HOST = "dl_popup";
const CATCHABLE = /^(https?|ftp):/i;   // blob:, data:, file: stay with Firefox
const bypass = new Set();              // URLs we deliberately give back to Firefox
const PDF_VIEWER = "pdf-zathura@samrudh.local";

let enabled = true;

function render() {
  browser.browserAction.setBadgeText({ text: enabled ? "" : "off" });
  browser.browserAction.setBadgeBackgroundColor({ color: "#f38ba8" });
  browser.browserAction.setTitle({
    title: enabled
      ? "dl-popup: catching downloads (click to pause)"
      : "dl-popup: paused, Firefox handles downloads (click to resume)",
  });
}

browser.storage.local.get("enabled").then((r) => {
  enabled = r.enabled !== false;
  render();
});

browser.browserAction.onClicked.addListener(() => {
  enabled = !enabled;
  browser.storage.local.set({ enabled });
  render();
});

browser.menus.create({
  id: "dl-popup",
  title: "Download with dl-popup",
  contexts: ["link", "video", "audio", "image"],
});

browser.menus.onClicked.addListener((info, tab) => {
  const url = info.linkUrl || info.srcUrl;
  if (!url || !CATCHABLE.test(url)) return;
  handOff({
    url,
    referrer: info.pageUrl || "",
    cookieStoreId: tab && tab.cookieStoreId,
    incognito: !!(tab && tab.incognito),
  });
});

browser.downloads.onCreated.addListener(async (item) => {
  const url = item.finalUrl || item.url;
  if (bypass.delete(url) || bypass.delete(item.url)) return;
  if (!enabled || !CATCHABLE.test(url)) return;

  await browser.downloads.cancel(item.id).catch(() => {});
  await browser.downloads.erase({ id: item.id }).catch(() => {});

  const filename = (item.filename || "").split(/[\\/]/).pop();
  handOff({
    url,
    filename,
    referrer: item.referrer || "",
    size: item.totalBytes,
    mime: item.mime || "",
    cookieStoreId: item.cookieStoreId,
    incognito: !!item.incognito,
    preview: !item.incognito && item.byExtensionId !== PDF_VIEWER &&
      (/pdf/i.test(item.mime || "") || /\.pdf$/i.test(filename)),
  });
});

async function handOff(job) {
  const query = { url: job.url, firstPartyDomain: null };
  if (job.cookieStoreId) query.storeId = job.cookieStoreId;
  const cookies = await browser.cookies.getAll(query).catch(() => []);

  const payload = {
    url: job.url,
    filename: job.filename || "",
    referrer: job.referrer || "",
    size: job.size,
    mime: job.mime || "",
    cookies: cookies.map((c) => `${c.name}=${c.value}`).join("; "),
    userAgent: navigator.userAgent,
    preview: !!job.preview,
  };

  let res;
  try {
    res = await browser.runtime.sendNativeMessage(HOST, { cmd: "add", job: payload });
  } catch (e) {
    console.error("dl-popup: native host failed", e);
    res = { action: "error", error: String(e) };
  }

  if (res && res.action === "preview" && job.preview) {
    const ok = await browser.runtime.sendMessage(PDF_VIEWER, {
      type: "preview", url: job.url, name: job.filename || "", cookieStoreId: job.cookieStoreId,
    }).catch((e) => console.error("dl-popup: PDF in Zathura did not answer", e));
    // Viewer not installed (or disabled): the popup again, without the row.
    if (!ok) handOff({ ...job, preview: false });
    return;
  }

  if (res && (res.action === "firefox" || res.action === "error")) {
    bypass.add(job.url);
    const opts = { url: job.url };
    if (job.filename) opts.filename = job.filename;
    if (job.incognito) opts.incognito = true;
    else if (job.cookieStoreId) opts.cookieStoreId = job.cookieStoreId;
    browser.downloads.download(opts).catch((e) => {
      bypass.delete(job.url);
      console.error("dl-popup: Firefox fallback failed", e);
    });
  }
}
