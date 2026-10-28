// Keeps host.py (native messaging, "firefox_tabs") up to date with every tab
// that has a YouTube / YouTube Music player, and which one the bar should
// show; passes host.py's commands on to the tabs. See ../README.md.
const HOST = "firefox_tabs";
const media = new Map();       // tabId -> state from tab.js
const titles = new Map();      // tabId -> tab title (host.py finds the window by it)
const active = new Map();      // windowId -> active tabId
let recent = [];               // tabIds, most recently switched to first
let focusedWin = browser.windows.WINDOW_ID_NONE;
let port = null;

// The tab the bar shows: the focused window's tab if it has a player, else
// the last tab you were on that has one, else whatever plays.
function current() {
  const a = active.get(focusedWin);
  if (a !== undefined && media.has(a)) return a;
  for (const t of recent) if (media.has(t)) return t;
  for (const [t, s] of media) if (s.playing) return t;
  return media.size ? [...media.keys()].pop() : null;
}

function push() {
  if (!port) return;
  const tabs = [...media].map(([tab, s]) => ({ ...s, tab, tabTitle: titles.get(tab) || "" }));
  port.postMessage({ type: "tabs", current: current(), tabs });
}

function connect() {
  port = browser.runtime.connectNative(HOST);
  port.onMessage.addListener(onHost);
  port.onDisconnect.addListener(() => {
    port = null;
    setTimeout(connect, 5000);    // host.py died / not installed: retry
  });
  push();
}

async function onHost(msg) {
  try {
    if (msg.cmd === "focus") {
      const tab = await browser.tabs.update(msg.tab, { active: true });
      await browser.windows.update(tab.windowId, { focused: true });
    } else {
      await browser.tabs.sendMessage(msg.tab, msg);
    }
  } catch (e) {
    media.delete(msg.tab);         // tab gone
    push();
  }
}

browser.runtime.onMessage.addListener((msg, sender) => {
  if (msg.type !== "media" || !sender.tab || sender.frameId !== 0) return;
  const id = sender.tab.id;
  titles.set(id, sender.tab.title || "");
  if (msg.state) media.set(id, msg.state);
  else media.delete(id);
  push();
});

browser.tabs.onActivated.addListener(({ tabId, windowId }) => {
  active.set(windowId, tabId);
  recent = [tabId, ...recent.filter((t) => t !== tabId)].slice(0, 50);
  push();
});
browser.windows.onFocusChanged.addListener((w) => {
  if (w === browser.windows.WINDOW_ID_NONE) return;   // left Firefox: keep the last one
  focusedWin = w;
  push();
});
browser.tabs.onRemoved.addListener((id) => {
  media.delete(id); titles.delete(id); recent = recent.filter((t) => t !== id);
  push();
});
browser.tabs.onUpdated.addListener((id, change) => {
  if (change.title === undefined) return;
  titles.set(id, change.title);
  if (media.has(id)) push();
}, { properties: ["title"] });

(async () => {
  const w = await browser.windows.getLastFocused().catch(() => null);
  if (w) focusedWin = w.id;
  for (const t of await browser.tabs.query({ active: true })) {
    active.set(t.windowId, t.id);
    recent.push(t.id);
  }
  connect();
  // Tabs that were already playing before we (re)started: ask them.
  for (const t of await browser.tabs.query({ url: ["*://*.youtube.com/*"] }))
    browser.tabs.sendMessage(t.id, { cmd: "report" }).catch(() => {});
})();
