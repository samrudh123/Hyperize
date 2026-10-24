// Runs in every frame. Reports whether what is fullscreen in THIS frame is a
// video (the player's fullscreen button), as opposed to F11 / SUPER+F, which
// make nothing fullscreen inside the page. An embedded player reports from
// its own frame: in the parent, the fullscreen element is just the <iframe>.
(() => {
  const api = globalThis.browser ?? chrome;

  // every <video> under el, including inside shadow roots (custom-element players)
  const videos = (root, out = []) => {
    out.push(...root.querySelectorAll("video"));
    for (const n of root.querySelectorAll("*")) if (n.shadowRoot) videos(n.shadowRoot, out);
    return out;
  };

  // A video counts when it fills a good part of the screen — not a page put
  // fullscreen that merely has a small clip somewhere on it.
  const isVideo = (el) => {
    if (el.tagName === "VIDEO") return true;
    if (el.tagName === "IFRAME") return false;
    const list = videos(el.shadowRoot ?? el);
    if (el.shadowRoot) videos(el, list);
    const screen = innerWidth * innerHeight;
    return list.some((v) => {
      const r = v.getBoundingClientRect();
      return r.width * r.height >= 0.4 * screen;
    });
  };

  let last = false;
  const check = () => {
    const el = document.fullscreenElement ?? document.webkitFullscreenElement;
    const now = !!el && isVideo(el);
    if (now === last) return;
    last = now;
    Promise.resolve(api.runtime.sendMessage({ videoFullscreen: now })).catch(() => {});
  };
  // the player may still be resizing when the event fires: look again shortly
  const onChange = () => {
    check();
    setTimeout(check, 250);
    setTimeout(check, 1000);
  };
  document.addEventListener("fullscreenchange", onChange, true);
  document.addEventListener("webkitfullscreenchange", onChange, true);
})();
