// Page world, every frame below the top one.
//
// A video player in an iframe (AnimeKai's megaplay.buzz / JW Player) sets
// navigator.mediaSession.metadata with an EMPTY title. Firefox then fills
// the title in from the top page's title — but only at the moment the
// metadata is set: later changes to the page title are ignored once a
// session has metadata (MediaStatusManager::NotifyPageTitleChanged), so the
// media notification (and, via KDE Connect, the laptop's playerctl) keeps
// the old title. Setting the same metadata again makes Firefox read the page
// title afresh. top.js says when, because this frame can't see the top
// page's title (other origin).
(() => {
  if (window === window.top || typeof MediaSession === "undefined") return;
  const desc = Object.getOwnPropertyDescriptor(MediaSession.prototype, "metadata");
  if (!desc || !desc.set) return;

  const untitled = () => {
    const md = desc.get.call(navigator.mediaSession);
    return md && !md.title ? md : null;
  };

  Object.defineProperty(MediaSession.prototype, "metadata", {
    ...desc,
    set(value) {
      desc.set.call(this, value);
      if (untitled()) window.top.postMessage("media-title-sync:untitled", "*");
    },
  });

  window.addEventListener("message", (e) => {
    if (e.source !== window.top || e.data !== "media-title-sync:refresh") return;
    const md = untitled();
    if (!md) return;
    desc.set.call(navigator.mediaSession, new MediaMetadata({
      title: "",
      artist: md.artist,
      album: md.album,
      artwork: Array.from(md.artwork, (a) => ({ src: a.src, sizes: a.sizes, type: a.type })),
    }));
  });
})();
