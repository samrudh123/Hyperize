// This tab's YouTube / YouTube Music player → the background page → host.py,
// which makes it an MPRIS player of its own (firefox.tab_<id>); and the
// commands coming back (play / pause / seek / next / prev).
// Isolated world (plain content script); position.js is the MAIN-world part.
(() => {
  const music = location.hostname === "music.youtube.com";
  const started = new WeakSet();               // videos that have played (sound on)
  let beat = 0;
  let last = null;                             // last state while a video was there
  const LOADING_MAX = 5000;                    // ms a loading next track keeps `last`
  let loadingSince = 0, loadingCheck = 0;

  // YouTube's ⏭ is often display:none (player layout) but still has the
  // next video's link and still works when clicked; ⏮ only exists in playlists.
  const usable = (el) => !!el && el.getAttribute("aria-disabled") !== "true" &&
    (el.hasAttribute("href") || getComputedStyle(el).display !== "none");

  // The video this tab is about: the one playing with sound, else the last
  // one that did. Muted autoplay previews (home page hover) never count.
  function video() {
    const vs = [...document.querySelectorAll("video")];
    return vs.find((v) => !v.paused && !v.muted && started.has(v))
        || vs.find((v) => started.has(v) && v.isConnected && v.duration > 0) || null;
  }

  // ── shuffle / repeat, as the page has them (the bar's ⇄ ⟲) ──
  // loop: "None" | "Playlist" | "Track"; shuffle: true / false; null = none here.
  //   YouTube playlist: the playlist panel's loop button (NONE -> ALL -> ONE;
  //     its aria-label is the label of the CURRENT state in the renderer's
  //     data.states — matched there, so any UI language works) and its
  //     shuffle toggle (aria-pressed);
  //   a single YouTube video: <video loop>, which YouTube's right-click
  //     "Loop" sets — Track or None ("Playlist" asked for becomes Track);
  //   YouTube Music: the player bar's repeatMode (NONE/ALL/ONE) and shuffleOn.
  // Checked against YouTube in a headless Firefox (2026-10-26).
  const LOOP_OF = {
    PLAYLIST_LOOP_STATE_NONE: "None", PLAYLIST_LOOP_STATE_ALL: "Playlist", PLAYLIST_LOOP_STATE_ONE: "Track",
    NONE: "None", ALL: "Playlist", ONE: "Track",
  };
  const LOOP_LABEL = {             // English fallback if data.states can't be read
    "Loop playlist": "PLAYLIST_LOOP_STATE_NONE", "Loop video": "PLAYLIST_LOOP_STATE_ALL",
    "Turn off loop": "PLAYLIST_LOOP_STATE_ONE",
  };
  const page = (el) => el && (el.wrappedJSObject || el);   // the page's own properties
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  function playlistPanel() {
    const ps = [...document.querySelectorAll("ytd-playlist-panel-renderer")]
      .filter((p) => p.querySelector("ytd-playlist-loop-button-renderer button"));
    return ps.find((p) => p.offsetParent !== null) || ps[0] || null;
  }
  function playlistLoop(panel) {
    const r = panel && panel.querySelector("ytd-playlist-loop-button-renderer");
    const b = r && r.querySelector("button");
    if (!b) return null;
    const label = b.getAttribute("aria-label");
    let state = null;
    try {
      const states = page(r).data.states;
      for (let i = 0; i < states.length; i++) {
        const st = states[i].playlistLoopButtonStateRenderer;
        if (st.button.buttonRenderer.accessibilityData.accessibilityData.label === label) state = st.state;
      }
    } catch (e) { /* layout changed: fall back to the English labels */ }
    state = state || LOOP_LABEL[label];
    return state && LOOP_OF[state] ? { button: b, loop: LOOP_OF[state] } : null;
  }
  const playlistShuffle = (panel) =>
    panel && panel.querySelector("#playlist-action-menu ytd-toggle-button-renderer button[aria-pressed]");
  const musicBar = () => document.querySelector("ytmusic-player-bar");

  function modes(v) {
    if (music) {
      const bar = page(musicBar());
      if (!bar) return { loop: null, shuffle: null };
      return { loop: LOOP_OF[bar.repeatMode || bar.repeatMode_] || null,
               shuffle: typeof bar.shuffleOn === "boolean" ? bar.shuffleOn : null };
    }
    const panel = playlistPanel();
    const pl = playlistLoop(panel);
    if (pl) {
      const sb = playlistShuffle(panel);
      return { loop: pl.loop, shuffle: sb ? sb.getAttribute("aria-pressed") === "true" : null };
    }
    return { loop: v && v.loop ? "Track" : "None", shuffle: null };
  }

  // Step YouTube's own buttons until they say what was asked (each click
  // moves one state on), so the page's UI and the bar agree.
  async function setLoop(want) {
    for (let i = 0; i < 3; i++) {
      const now = modes(video()).loop;
      if (now === null || now === want) break;
      if (music) {
        const b = musicBar() && musicBar().querySelector(".repeat");
        if (!b) break;
        b.click();
      } else {
        const pl = playlistLoop(playlistPanel());
        if (!pl) {                                   // a single video: <video loop>
          const v = video();
          if (v) v.loop = want !== "None";
          break;
        }
        pl.button.click();
      }
      await sleep(250);
    }
    report();
  }
  async function setShuffle(want) {
    const now = modes(video()).shuffle;
    if (now !== null && now !== want) {
      const b = music ? musicBar() && musicBar().querySelector(".shuffle")
                      : playlistShuffle(playlistPanel());
      if (b) b.click();
      await sleep(250);
    }
    report();
  }

  function state() {
    const v = video();
    if (!v || !(v.duration > 0)) {
      // The video went away but the page didn't (YouTube tore its player
      // down): keep the tab's player, paused, so ⏯ can bring it back.
      if (last && last.url === location.href) return { ...last, playing: false };
      // A <video> that played is loading the NEXT track (YouTube Music's
      // shuffle starts a new song; next / prev): paused, no duration, new
      // URL for ~0.7 s (measured). Keep the player with its clock stopped,
      // rather than drop it — the bar's pill blinked out. At most LOADING_MAX.
      const loading = [...document.querySelectorAll("video")]
        .find((x) => started.has(x) && x.isConnected);
      if (last && loading) {
        loadingSince = loadingSince || Date.now();
        if (Date.now() - loadingSince < LOADING_MAX) {
          clearTimeout(loadingCheck);
          loadingCheck = setTimeout(report, LOADING_MAX + 100);
          return { ...last, stalled: true };
        }
      }
      return (last = null);
    }
    loadingSince = 0;
    const md = navigator.mediaSession && navigator.mediaSession.metadata;
    const art = md && md.artwork && md.artwork.length ? md.artwork[md.artwork.length - 1].src : "";
    const title = (md && md.title) ||
      document.title.replace(/^\(\d+\)\s*/, "").replace(/\s+-\s+YouTube( Music)?$/, "");
    return last = {
      title,
      artist: (md && md.artist) || "",
      album: (md && md.album) || "",
      art,
      url: location.href,
      duration: isFinite(v.duration) ? v.duration : 0,     // live: no length
      position: v.currentTime,
      playing: !v.paused,
      // buffering (after a seek, a slow network): host.py stops its clock
      stalled: v.readyState < 3,
      rate: v.playbackRate || 1,
      canNext: music ? true : usable(document.querySelector(".ytp-next-button")),
      canPrev: music ? true : usable(document.querySelector(".ytp-prev-button")),
      ...modes(v),
    };
  }

  function report() {
    browser.runtime.sendMessage({ type: "media", state: state() }).catch(() => {});
    clearInterval(beat);
    const v = video();
    // While playing, a correction every 10 s (host.py runs the clock itself).
    if (v && !v.paused) beat = setInterval(report, 10000);
  }

  for (const ev of ["play", "playing", "pause", "seeked", "waiting", "canplay", "ratechange", "durationchange", "ended", "emptied"])
    document.addEventListener(ev, (e) => {
      const v = e.target;
      if (!(v instanceof HTMLMediaElement)) return;
      if (ev === "playing" && !v.muted) started.add(v);
      report();
    }, true);
  // New video in the same tab (YouTube navigates without reloading): the
  // title changes before/after the media events — report it too.
  const watchTitle = () => {
    const t = document.querySelector("title");
    if (t) new MutationObserver(() => report()).observe(t, { childList: true });
    else setTimeout(watchTitle, 500);
  };
  watchTitle();
  // Shuffle / repeat changed on the page itself (YouTube's buttons, the
  // right-click "Loop"): no media event for that — re-report after a click.
  document.addEventListener("click", () => setTimeout(report, 400), true);

  const playButton = () => {
    const b = document.querySelector(music ? "#play-pause-button" : ".ytp-play-button");
    if (b) b.click();
  };

  browser.runtime.onMessage.addListener((msg) => {
    const v = video();
    switch (msg.cmd) {
      case "report": report(); return;
      case "play":
        if (v && v.readyState > 0) v.play().catch(() => {});
        else playButton();                       // unloaded: let YouTube reload it
        return;
      case "pause": if (v) v.pause(); return;
      case "seek": if (v) v.currentTime = msg.position; return;
      case "next": {
        const b = document.querySelector(music ? ".next-button" : ".ytp-next-button");
        if (b) b.click();
        return;
      }
      case "loop": setLoop(msg.value); return;
      case "shuffle": setShuffle(!!msg.value); return;
      case "prev": {
        const b = document.querySelector(music ? ".previous-button" : ".ytp-prev-button");
        if (b && (music || usable(b))) b.click();
        else if (v) v.currentTime = 0;
        return;
      }
    }
  });
  window.addEventListener("pagehide", () =>
    browser.runtime.sendMessage({ type: "media", state: null }).catch(() => {}));
})();
