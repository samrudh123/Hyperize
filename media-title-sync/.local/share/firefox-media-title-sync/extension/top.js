// Top frame. Two jobs, both only once the page plays media (a frame below
// reports untitled metadata — frame.js — or a <video>/<audio> in the page
// itself starts); pages without media are never watched.
//
// 1. Stale page titles. Streaming sites switch episodes without reloading
//    (history.pushState) and leave document.title on the episode the page
//    was opened on (AnimeKai, AnimeSuge, …), and Firefox names the media
//    after it. When the address changes and the site hasn't changed the
//    title FETCH_AFTER ms later, fetch the new address — as the page, with
//    its cookies — and use the <title> the site serves for it.
// 2. Firefox keeps a player iframe's title from when its metadata was set
//    (see frame.js), so on every title change tell those frames to set their
//    metadata again.
(() => {
  if (window !== window.top) return;

  const FETCH_AFTER = 1500;
  const FETCH_GAP = 5000;            // at most one fetch per this many ms
  // interstitials served instead of the page: never take their titles
  const NOT_A_TITLE = /^(just a moment|attention required|access denied|checking your browser|ddos-guard|404|403)\b/i;

  const frames = new Set();
  const known = new Map();           // address -> title fetched for it
  let watching = false;
  let title = null;
  let addr = "";
  let navAt = 0;
  let titleAtNav = "";
  let lastFetch = 0;

  const here = () => location.href.split("#")[0];

  function watch() {
    if (watching) return;
    watching = true;
    title = document.title;
    addr = here();
    setInterval(tick, 500);
  }

  window.addEventListener("message", (e) => {
    if (e.data !== "media-title-sync:untitled" || !e.source || e.source === window) return;
    frames.add(e.source);
    watch();
  });
  document.addEventListener("play", watch, true);     // media events don't bubble; capture does

  function tick() {
    if (here() !== addr) {
      addr = here();
      navAt = Date.now();
      titleAtNav = document.title;
    }
    if (navAt && Date.now() - navAt >= FETCH_AFTER) {
      navAt = 0;
      if (document.title === titleAtNav) fix(addr, titleAtNav);
    }
    if (document.title !== title) {
      title = document.title;
      for (const f of frames) {
        if (f.closed) frames.delete(f);
        else f.postMessage("media-title-sync:refresh", "*");
      }
    }
  }

  async function fix(url, stale) {
    let t = known.get(url);
    if (t === undefined) {
      if (Date.now() - lastFetch < FETCH_GAP) return;
      lastFetch = Date.now();
      t = await fetchTitle(url);
      known.set(url, t);
    }
    // only if we're still there and the site hasn't set a title meanwhile
    if (t && t !== stale && here() === url && document.title === stale) document.title = t;
  }

  async function fetchTitle(url) {
    try {
      // content.fetch = the page's own fetch (its cookies, its referrer)
      const get = typeof content !== "undefined" && content.fetch ? content.fetch.bind(content) : fetch;
      const r = await get(url, { credentials: "include" });
      if (!r.ok || !/html/i.test(r.headers.get("content-type") || "")) return "";
      const html = await r.text();
      const m = /<title[^>]*>([\s\S]*?)<\/title>/i.exec(html);
      if (!m) return "";
      const t = new DOMParser().parseFromString("<title>" + m[1] + "</title>", "text/html").title.trim();
      return NOT_A_TITLE.test(t) ? "" : t;
    } catch (e) {
      return "";
    }
  }
})();
