// Firefox → MPRIS length/position for YouTube (see ../README.md).
//
// Firefox only gives MPRIS a length/position — what the bottom bar's progress
// line draws (~/.config/hypr/now-playing.py) — when the PAGE reports them with
// navigator.mediaSession.setPositionState(). YouTube does that unreliably:
// after an ad, or at random, Firefox had the title but no length and a
// position stuck near 0, so no line (seen in 4 of 9 test runs). This reports them straight from the
// <video> that is playing, and drops YouTube's own (sometimes wrong) calls.
// Runs in the page's world (manifest "world": "MAIN"), at document_start.
(() => {
  const ms = navigator.mediaSession;
  if (!ms || !ms.setPositionState) return;
  const set = ms.setPositionState.bind(ms);
  ms.setPositionState = () => {};                // ours win
  let last = 0;
  const push = (v, force) => {
    if (!(v instanceof HTMLMediaElement) || v.muted) return;   // hover previews are muted
    const d = v.duration;
    if (!isFinite(d) || d <= 0) return;          // live stream / not loaded yet
    const now = performance.now();
    if (!force && now - last < 5000) return;     // Firefox extrapolates in between
    last = now;
    // Paused: a near-zero rate (0 isn't allowed). Firefox 156 runs its MPRIS
    // clock on while paused, whatever mediaSession.playbackState says.
    const rate = v.paused ? 1e-6 : v.playbackRate || 1;
    try {
      set({ duration: d, playbackRate: rate, position: Math.min(v.currentTime, d) });
    } catch (e) {}
  };
  // Media events don't bubble: listen in the capture phase.
  for (const ev of ["play", "playing", "pause", "seeked", "ratechange", "durationchange", "loadedmetadata", "ended"])
    document.addEventListener(ev, (e) => push(e.target, true), true);
  document.addEventListener("timeupdate", (e) => push(e.target, false), true);
  if (document.documentElement)                           // "is it running?" — devtools
    document.documentElement.dataset.mprisPosition = "1";
})();
