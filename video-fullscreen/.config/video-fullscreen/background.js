// Forwards each frame's "a video is (no longer) fullscreen" to the native host
// (~/.config/hypr/video-fullscreen.py), which tags / untags the browser's
// fullscreen window so Hyprland draws it opaque. Stateless on purpose: Brave
// suspends this service worker when idle, and the host's follower drops the
// tag by itself when the window leaves fullscreen.
const api = globalThis.browser ?? chrome;

api.runtime.onMessage.addListener((msg, sender) => {
  if (!sender.tab || typeof msg?.videoFullscreen !== "boolean") return;
  Promise.resolve(api.runtime.sendNativeMessage("video_fullscreen", { fullscreen: msg.videoFullscreen }))
    .catch((e) => console.warn("video_fullscreen host:", e));
});
