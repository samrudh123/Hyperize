// AnimeKai switches episodes without reloading (history.pushState) and
// leaves document.title on the episode the page was opened on, so the tab
// and the media notification said "Episode 8" while episode 9 played. Put
// the episode from the URL (/watch/<anime>/ep-9) into the title; top.js then
// passes the change on to the player.
(() => {
  if (window !== window.top) return;
  const LAST_EPISODE = /Episode [\d.]+(?!.*Episode [\d.]+)/;

  function fix() {
    const m = location.pathname.match(/\/watch\/[^/]+\/ep-([\d.]+)/);
    if (!m || !LAST_EPISODE.test(document.title)) return;
    const want = document.title.replace(LAST_EPISODE, `Episode ${m[1]}`);
    if (want !== document.title) document.title = want;
  }

  fix();
  setInterval(fix, 500);
  window.addEventListener("popstate", fix);
})();
