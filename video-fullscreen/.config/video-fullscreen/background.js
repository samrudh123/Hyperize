// On a fullscreen change in a tab, look into EVERY frame of it and decide
// whether a video is what's fullscreen; tell the native host
// (~/.config/hypr/video-fullscreen.py), which tags / untags the browser's
// fullscreen window so Hyprland draws it opaque.
//
// Looking from here rather than from each frame catches the layouts streaming
// sites use: the page fullscreens the <iframe> holding the player (or a box
// around it), so inside the player's frame nothing is fullscreen and up top
// the fullscreen element holds no <video> of its own.
//
// Stateless apart from the last answer per tab (a restarted Brave service
// worker just sends again); the host's follower drops the tag by itself when
// the window leaves fullscreen.
const api = globalThis.browser ?? chrome;
const MV3 = api.runtime.getManifest().manifest_version === 3;

// Runs inside each frame; must be self-contained (it is serialised).
function probe() {
  const screen = (innerWidth * innerHeight) || 1;
  const big = (el) => {
    const r = el.getBoundingClientRect();
    return r.width * r.height >= 0.2 * screen;
  };
  // matches under root, shadow roots (custom-element players) included
  const all = (root, sel, out = []) => {
    out.push(...root.querySelectorAll(sel));
    for (const n of root.querySelectorAll("*")) if (n.shadowRoot) all(n.shadowRoot, sel, out);
    return out;
  };
  const fs = document.fullscreenElement ?? document.webkitFullscreenElement ?? null;
  let kind = null;
  if (fs) {
    const under = (sel) => [
      ...(fs.matches(sel) ? [fs] : []),
      ...all(fs, sel),
      ...(fs.shadowRoot ? all(fs.shadowRoot, sel) : []),
    ];
    if (under("video").some(big)) kind = "video";
    else if (under("iframe, frame, embed, object").some(big)) kind = "frame";
    else kind = "other";
  }
  // any big <video> counts, loaded or not: a player fullscreened before Play
  // is pressed has not loaded anything yet
  return { kind, video: all(document, "video").some(big) };
}

function probeAll(tabId) {
  if (MV3)
    return api.scripting
      .executeScript({ target: { tabId, allFrames: true }, func: probe })
      .then((rs) => rs.map((r) => r.result).filter(Boolean));
  return api.tabs.executeScript(tabId, { code: `(${probe})()`, allFrames: true, matchAboutBlank: true })
    .then((rs) => rs.filter(Boolean));
}

// A video is fullscreen when the fullscreen element holds a big <video>, or
// holds a big frame and some frame in the tab shows a big <video>.
const decide = (rs) =>
  rs.some((r) => r.kind === "video") ||
  (rs.some((r) => r.kind === "frame") && rs.some((r) => r.video));

const sent = new Map();     // tabId -> last answer given to the host

async function check(tabId) {
  let on = false;
  try {
    on = decide(await probeAll(tabId));
  } catch (e) {
    // a frame we may not script (about:, the PDF viewer, …): treat as no video
  }
  if (sent.get(tabId) === on) return;
  sent.set(tabId, on);
  Promise.resolve(api.runtime.sendNativeMessage("video_fullscreen", { fullscreen: on }))
    .catch((e) => console.warn("video_fullscreen host:", e));
}

api.runtime.onMessage.addListener((msg, sender) => {
  if (!msg?.fullscreenChanged || sender.tab?.id === undefined) return;
  const id = sender.tab.id;
  // players often resize, or load the <video>, a moment after the event
  for (const ms of [0, 300, 1200]) setTimeout(() => check(id), ms);
});

api.tabs.onRemoved.addListener((id) => sent.delete(id));

// Chromium doesn't put content scripts into tabs that were already open when
// the extension was installed / reloaded (Firefox does): add ours to them.
if (MV3)
  api.runtime.onInstalled.addListener(async () => {
    for (const tab of await api.tabs.query({}))
      api.scripting.executeScript({ target: { tabId: tab.id }, files: ["content.js"] }).catch(() => {});
  });
