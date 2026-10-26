// Top frame only: tell the background page that something in this tab went
// in or out of fullscreen. The top document sees every DOM fullscreen change
// in the tab — an embedded player going fullscreen fullscreens its <iframe>
// up here too. F11 / SUPER+F make nothing fullscreen inside the page, so they
// never fire this. Whether it is a VIDEO is decided by the background page,
// which can look into every frame (cross-origin ones included).
(() => {
  const api = globalThis.browser ?? chrome;
  const ping = () =>
    Promise.resolve(api.runtime.sendMessage({ fullscreenChanged: true })).catch(() => {});
  document.addEventListener("fullscreenchange", ping, true);
  document.addEventListener("webkitfullscreenchange", ping, true);
})();
