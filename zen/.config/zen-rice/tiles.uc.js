// Zen tiling workspaces — the Hyprland desktop, inside the browser.
//
// A "workspace" is one entry of Zen's tab list: a single tab, or a split view
// (Zen's tiling: several tabs shown side by side as one entry). This script,
// loaded into every browser window by rice-live.cfg (the autoconfig, see
// README.md), makes those behave like the desktop's workspaces:
//
//   Ctrl+T            new tile IN this workspace (a blank one too), where the cursor is: like
//                     Hyprland's dwindle, it splits the tile under the cursor
//                     (side by side if wider than tall, else stacked) and takes
//                     the cursor's half; then the URL bar has focus
//   Alt+N             go to the next EMPTY workspace (a new-tab page). There is
//                     only ever one: an empty workspace you leave is closed, so
//                     you cannot reach a second one until you search in this one
//   Alt+1 … Alt+9, 0  the 1st … 10th workspace from the top of the tab list
//                     (SUPER+1…0); Alt+Shift+1 … 0 moves the focused tile there —
//                     a number past the last workspace makes a new one at the
//                     bottom (the desktop's stacked workspaces)
//   Alt + drag        move a tile of a split with the mouse / touchpad (SUPER+drag)
//   links             a tab a page opens becomes a tile of that page's workspace,
//                     or a new workspace when it is full
//   Ctrl+Tab          next tile of THIS workspace (reading order), wrapping;
//                     Ctrl+Shift+Tab the other way. A lone tab stays put
//   (starting Zen, or a new window, lands on the most recently used workspace
//   instead of a new tab)
//   Alt+Tab           the workspace picker (the desktop pickers' slanted cards)
//   Alt+PgUp / PgDn   one workspace up / down the tab list, no wrapping: up from
//                     the top opens a new (empty) workspace at the top, down from
//                     the bottom does nothing. 3-finger swipe up / down sends
//                     these (hypr/zen-swipe.sh)
//   mouse             moving the cursor onto another tile focuses it (follow_mouse)
//   animations        Hyprland's own, read from hyprland.conf: tiles pop in (windowsIn),
//                     slide/resize into place (windows), shrink + fade out (windowsOut);
//                     switching workspace crossfades (workspacesIn / workspacesOut)
//   Alt+arrows, Alt+H/J/K/L   focus the tile in that direction  (SUPER+arrows)
//   Alt+Shift+arrows  move the tile that way, dwindle's movewindow (SUPER+SHIFT+arrows)
//   Alt+Ctrl+arrows   resize the tile 40 px: → ↓ grow, ← ↑ shrink (SUPER+CTRL+arrows)
//                     (the arrow keys only act inside a split view: on a lone tab
//                     Ctrl+Alt+←/→ stay Zen's space switch)
//   Ctrl+← / Ctrl+→   back / forward (customKeys.json rebinds goBackKb/goForwardKb
//                     from Alt+←/→; this script covers a focused page, whose own
//                     Ctrl+←/→ word jump would eat them). A text field keeps the
//                     word jump, in the page and in the URL bar
//   Alt+T             flip the focused tile's split row ↔ column (togglesplit)
//   Ctrl+W            closes the focused tile (Zen's own; the others re-tile)
//
// Picker (Alt+Tab): cards in tab-list order, numbered like Alt+1 … Alt+0, the
// one you are on selected, and a "+" card at the end for the next empty one.
//   Tab / Shift+Tab, ← → / h l, wheel   move      Enter / click     go there
//   hold Alt and tap Tab, let go of Alt  go to the card you tabbed to
//   1-9, 0  select that card          m  carry the focused tile along (Shift+Enter once)
//   x / Delete  close that workspace  /  search titles + addresses (Esc clears)
//   Esc / q / right click / click outside  close
//
// Up to MAX_TILES tiles per workspace (Zen's own limit is 4).
// Errors go to the Browser Console as "tiles.uc.js: …".
(function () {
  "use strict";
  if (window.riceTiles || location.href !== "chrome://browser/content/browser.xhtml") return;

  const MAX_TILES = 8;
  const XHTML = "http://www.w3.org/1999/xhtml";
  const NEWTAB = new Set(["about:newtab", "about:home", "about:privatebrowsing"]);
  const S = () => window.gZenViewSplitter;
  const log = (e) => console.error("tiles.uc.js:", e);

  function el(tag, cls, parent, text) {
    const e = document.createElementNS(XHTML, tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    if (parent) parent.appendChild(e);
    return e;
  }

  // ── the model ────────────────────────────────────────────────────────────

  function groupOf(tab) {
    return (S() && S()._data.find((g) => g.tabs.includes(tab))) || null;
  }

  // inside a collapsed Zen folder (the selected tab still shows there)
  function folded(tab) {
    for (let g = tab.group; g; g = g.group) {
      if (!g.hasAttribute("split-view-group") && g.collapsed) return !tab.selected;
    }
    return false;
  }

  function usable(tab) {
    return tab && tab.isConnected && !tab.hidden && !tab.closing &&
      !tab.hasAttribute("zen-empty-tab") && !tab.hasAttribute("zen-glance-tab");
  }

  // the tab the user is on (a Glance popup counts as its parent tab)
  function current() {
    const t = gBrowser.selectedTab;
    try { return window.gZenGlanceManager?.getTabOrGlanceParent(t) || t; } catch (e) { return t; }
  }

  // A new-tab page that was never used: no history, nothing loading, not part
  // of a split, not pinned. Zen's own hidden empty tab counts as well.
  function isEmptyWs(tab) {
    if (!tab) return false;
    if (tab.hasAttribute("zen-empty-tab")) return true;
    if (tab.pinned || tab.hasAttribute("zen-essential") || tab.splitView || groupOf(tab)) return false;
    if (tab.hasAttribute("pending") || tab.hasAttribute("busy")) return false;
    const b = tab.linkedBrowser;
    if (!b || !NEWTAB.has(b.currentURI?.spec || "")) return false;
    return !(b.canGoBack || b.canGoForward);
  }

  function recency(tab) {
    return tab.selected ? Infinity : tab.lastAccessed || 0;
  }

  // Every workspace of the current Zen space, in list order.
  function units() {
    const seen = new Map(), out = [], cur = current();
    for (const tab of gBrowser.visibleTabs) {
      if (!usable(tab) || folded(tab)) continue;
      const g = groupOf(tab);
      const key = g || tab;
      if (seen.has(key)) continue;
      const tabs = g ? g.tabs.filter(usable) : [tab];
      if (!tabs.length) continue;
      const u = { key, group: g, tabs };
      u.focus = tabs.reduce((a, b) => (recency(b) > recency(a) ? b : a));
      u.current = tabs.includes(cur);
      u.empty = !g && isEmptyWs(tabs[0]);
      seen.set(key, u);
      out.push(u);
    }
    return out;
  }

  // the most recently used workspace other than an empty one
  function mostRecent() {
    let best = null;
    for (const u of units()) if (!u.empty && (!best || recency(u.focus) > recency(best.focus))) best = u;
    return best;
  }

  // Starting Zen (or opening a window) shows the last workspace you used, not
  // a new tab / Zen's empty tab. Only acts while the window is still empty-
  // handed, so a link another app opened, or a session's own selection, wins.
  function landOnRecent() {
    try {
      if (!isEmptyWs(current())) return;
      const u = mostRecent();
      if (!u) return;
      gBrowser.selectedTab = u.focus;
      // and the start-up new-tab pages nobody is looking at go, as empty workspaces do
      for (const t of gBrowser.tabs.slice())
        if (!t.selected && !t.hasAttribute("zen-empty-tab") && isEmptyWs(t) && gBrowser.tabs.length > 1)
          gBrowser.removeTab(t, { animate: false, skipSessionStore: true });
      setTimeout(() => { try { if (gURLBar.view?.isOpen) gURLBar.view.close(); gBrowser.selectedBrowser.focus(); } catch (e) {} }, 60);
    } catch (e) { log(e); }
  }

  // Zen settles on its start-up tab some time after the window opens (spaces
  // restore, the home page loading): keep checking for a few seconds, until
  // you press a key or click.
  function watchStartup() {
    let stop = false;
    const off = () => { stop = true; };
    window.addEventListener("keydown", off, { capture: true, once: true });
    window.addEventListener("mousedown", off, { capture: true, once: true });
    const end = Date.now() + 6000;
    const tick = () => {
      if (stop || window.closed || Date.now() > end) return;
      landOnRecent();
      // a caret left in the (untouched) URL bar over a real page: give the
      // page the keyboard, as the desktop does for a window you land on
      try {
        if (gURLBar.focused && !gURLBar.view?.isOpen && !gBrowser.userTypedValue && !isEmptyWs(current()))
          gBrowser.selectedBrowser.focus();
      } catch (e) {}
      setTimeout(tick, 200);
    };
    tick();
  }

  // Ctrl+Tab / Ctrl+Shift+Tab: the tiles of this workspace in reading order
  function cycleTile(dir) {
    const cur = current(), g = groupOf(cur);
    if (!g) return;
    const order = rects(g.layoutTree).map((r) => r.tab).filter(usable);
    const i = order.indexOf(cur);
    if (order.length < 2 || i < 0) return;
    const t = order[(i + dir + order.length) % order.length];
    gBrowser.selectedTab = t;
    setTimeout(() => t.linkedBrowser.focus(), 0);
  }

  // ── layout trees (Zen's nsSplitNode: direction row|column, children with
  //    sizeInParent in % along the parent's direction; leaves carry .tab) ──

  function findLeaf(node, tab) {
    if (!node) return null;
    if (!node.children) return node.tab === tab ? node : null;
    for (const c of node.children) {
      const r = findLeaf(c, tab);
      if (r) return r;
    }
    return null;
  }

  // every leaf's rectangle as fractions of the whole view
  function rects(node, x = 0, y = 0, w = 1, h = 1, out = []) {
    if (!node) return out;
    if (!node.children) {
      out.push({ tab: node.tab, x, y, w, h });
      return out;
    }
    let off = 0;
    for (const c of node.children) {
      const f = (c.sizeInParent || 100 / node.children.length) / 100;
      if (node.direction === "row") rects(c, x + off * w, y, f * w, h, out);
      else rects(c, x, y + off * h, w, f * h, out);
      off += f;
    }
    return out;
  }

  // the page area, in window (client) pixels
  function panelRect() {
    const p = document.getElementById("tabbrowser-tabpanels");
    const r = p ? p.getBoundingClientRect() : null;
    return r && r.width > 0 ? { x: r.left, y: r.top, w: r.width, h: r.height }
      : { x: 0, y: 0, w: window.innerWidth, h: window.innerHeight };
  }

  function panelSize() {
    const r = panelRect();
    return { w: r.w, h: r.h };
  }

  // the tiles of a workspace (a split's group, or just `tab`) in client pixels
  function tilePx(g, tab) {
    const p = panelRect();
    if (!g) return [{ tab, x: p.x, y: p.y, w: p.w, h: p.h }];
    return rects(g.layoutTree).map((r) => ({ tab: r.tab, x: p.x + r.x * p.w, y: p.y + r.y * p.h, w: r.w * p.w, h: r.h * p.h }));
  }

  function hit(list, pt) {
    return (pt && list.find((r) => pt.x >= r.x && pt.x < r.x + r.w && pt.y >= r.y && pt.y < r.y + r.h)) || null;
  }

  // Hyprland's dwindle placement (force_split 0, split_width_multiplier 1):
  // the tile splits side by side when it is wider than tall, else stacked,
  // and the new one takes the half the point (the cursor) is in. No point →
  // right / bottom.
  function placeAt(r, pt) {
    const wide = r.w > r.h;
    if (!pt) return wide ? "right" : "bottom";
    return wide ? (pt.x < r.x + r.w / 2 ? "left" : "right") : (pt.y < r.y + r.h / 2 ? "top" : "bottom");
  }

  // a node's rectangle (fractions of the view), for resizing
  function boxOf(node, target, x = 0, y = 0, w = 1, h = 1) {
    if (node === target) return { x, y, w, h };
    if (!node.children) return null;
    let off = 0;
    for (const c of node.children) {
      const f = (c.sizeInParent || 100 / node.children.length) / 100;
      const r = node.direction === "row" ? boxOf(c, target, x + off * w, y, f * w, h)
        : boxOf(c, target, x, y + off * h, w, f * h);
      if (r) return r;
      off += f;
    }
    return null;
  }

  // where the cursor last was over this window (client px); null once it leaves
  let mouse = null;

  // Zen wants no node with the same direction as its parent and no node with
  // one child; fold those away after we rearrange things.
  function normalize(g) {
    const fix = (node) => {
      if (!node.children) return node;
      const kids = [];
      for (let c of node.children) {
        c = fix(c);
        if (c.children && c.direction === node.direction) {
          for (const cc of c.children) {
            cc.sizeInParent *= c.sizeInParent / 100;
            kids.push(cc);
          }
        } else kids.push(c);
      }
      if (kids.length === 1) {
        kids[0].sizeInParent = node.sizeInParent;
        return kids[0];
      }
      node.children = kids;        // the setter re-parents
      return node;
    };
    const root = fix(g.layoutTree);
    root.parent = null;
    root.positionToRoot = null;
    g.layoutTree = root;
  }

  function relayout(g) {
    normalize(g);
    const sp = S();
    if (sp._data.indexOf(g) === sp.currentView) sp.activateSplitView(g, true);
  }

  // ── actions ──────────────────────────────────────────────────────────────

  function focusUrlbar() {
    setTimeout(() => {
      try { window.focusAndSelectUrlBar ? window.focusAndSelectUrlBar() : gURLBar.select(); } catch (e) { log(e); }
    }, 30);
  }

  // Put `tab` into `anchor`'s workspace, next to `anchor`.
  function insertTile(anchor, tab, side) {
    const sp = S();
    if (anchor.pinned && !tab.pinned) gBrowser.pinTab(tab);
    else if (!anchor.pinned && tab.pinned) gBrowser.unpinTab(tab);
    const g = groupOf(anchor);
    if (!g) {
      const first = side === "left" || side === "top";
      sp.splitTabs(first ? [tab, anchor] : [anchor, tab],
                   side === "left" || side === "right" ? "vsep" : "hsep", first ? 0 : 1);
      return;
    }
    sp.splitTabs([anchor, tab], undefined, 1);           // appended to the root…
    const g2 = groupOf(tab);
    if (!g2) return;
    const leaf = findLeaf(g2.layoutTree, tab);
    if (!leaf || !findLeaf(g2.layoutTree, anchor)) return;
    sp.removeNode(leaf);                                    // …so re-home it
    sp.splitIntoNode(findLeaf(g2.layoutTree, anchor), leaf, side, 0.5);
    relayout(g2);
  }

  function full(g) {
    if (g && g.tabs.length >= S().MAX_TABS) {
      toast(`This workspace is full (${S().MAX_TABS} tiles)`);
      return true;
    }
    return false;
  }

  // Ctrl+T: the new tile opens where the cursor is — it splits the tile under
  // the cursor, on the cursor's half (focus follows the mouse on the desktop,
  // so that's the tile Hyprland would split). Cursor elsewhere: the focused
  // tile, right / bottom.
  function tileNew() {
    const cur = current();
    // Zen's own hidden empty tab can't be tiled: make it a real blank page
    // first (the next Ctrl+T then tiles next to it). A blank new-tab page
    // tiles like any other tab, so a fresh workspace can be filled with
    // blank tiles before searching in them.
    if (cur.hasAttribute("zen-empty-tab")) {
      gBrowser.selectedTab = gBrowser.addTrustedTab(window.BROWSER_NEW_TAB_URL || "about:newtab");
      return focusUrlbar();
    }
    if (cur.hasAttribute("zen-essential")) return newWorkspace();
    const g = groupOf(cur);
    if (full(g)) return;
    const list = tilePx(g, cur);
    const under = hit(list, mouse);
    const anchor = under ? under.tab : cur;
    const side = placeAt(under || list.find((r) => r.tab === cur) || list[0], under ? mouse : null);
    ownTabs++;
    const tab = gBrowser.addTrustedTab(window.BROWSER_NEW_TAB_URL || "about:newtab", {
      index: anchor._tPos + 1,
      skipAnimation: true,
    });
    ownTabs--;
    insertTile(anchor, tab, side);
    gBrowser.selectedTab = tab;
    focusUrlbar();
  }

  // Alt+N: the one empty workspace — this one, the existing one, or a new one
  function newWorkspace(top = false) {
    if (isEmptyWs(current())) return focusUrlbar();
    const e = units().find((u) => u.empty);
    if (e) {
      gBrowser.selectedTab = e.tabs[0];
      return focusUrlbar();
    }
    ownTabs++;
    try {
      window.BrowserCommands.openTab();
    } catch (err) {
      gBrowser.selectedTab = gBrowser.addTrustedTab(window.BROWSER_NEW_TAB_URL || "about:newtab");
    } finally { ownTabs--; }
    if (top) toTop(gBrowser.selectedTab);
    focusUrlbar();
  }

  function go(u) {
    if (!u || u === "new") return crossfade(() => newWorkspace());
    if (u.current) return;
    crossfade(() => { gBrowser.selectedTab = u.focus; });
  }

  // Alt+Shift+N / the picker's carry: the focused tile goes to `dest`
  function moveTile(dest) {
    const sp = S(), tab = current();
    if (!dest || isEmptyWs(tab)) return;
    if (tab.hasAttribute("zen-essential")) return toast("Essentials can't be tiled");
    if (dest !== "new" && dest.tabs.includes(tab)) return;
    if (dest !== "new" && !dest.empty && full(dest.group)) return;
    const g = groupOf(tab);
    if (!g && dest !== "new" && dest.empty) return;       // already a workspace of its own
    if (g) sp.removeTabFromGroup(tab, sp._data.indexOf(g), { forUnsplit: true, changeTab: false });
    if (dest === "new" || dest.empty) {
      const old = dest !== "new" ? dest.tabs[0] : null;
      if (dest === "new") toBottom(tab);                    // the new last workspace
      gBrowser.selectedTab = tab;
      if (old && old !== tab) gBrowser.removeTab(old, { animate: false, skipSessionStore: true });
      return;
    }
    insertTile(dest.focus, tab, placeAt(tilePx(dest.group, dest.focus).find((r) => r.tab === dest.focus), null));
    gBrowser.selectedTab = tab;
  }

  // Alt+PgUp / PgDn (3-finger swipe up / down): one workspace up / down the
  // tab list, no wrapping. Up from the top workspace opens the empty one (a
  // new tab, put at the top of the list); down from the bottom does nothing.
  function step(dir) {
    const us = units();
    const i = us.findIndex((u) => u.current);
    if (i < 0) {                         // on Zen's hidden empty tab: above the top
      if (dir > 0 && us.length) go(us[0]);
      return;
    }
    const j = i + dir;
    if (j >= us.length) return;
    if (j >= 0) return go(us[j]);
    if (!us[i].empty) crossfade(() => newWorkspace(true));
  }

  // move `tab` below every other workspace of this space (unpinning it)
  function toBottom(tab) {
    try {
      if (tab.pinned) gBrowser.unpinTab(tab);
      const others = gBrowser.visibleTabs.filter((t) => t !== tab && usable(t) && !folded(t));
      const last = others[others.length - 1];
      if (!last || tab._tPos > last._tPos) return;
      let target = last;
      while (target.group) target = target.group;    // after its split / folder, not into it
      gBrowser.moveTabAfter(tab, target);
    } catch (e) { log(e); }
  }

  // move `tab` above every other unpinned workspace of this space
  function toTop(tab) {
    try {
      const first = gBrowser.visibleTabs.find((t) => t !== tab && usable(t) && !t.pinned && !t.hasAttribute("zen-essential"));
      if (!first || tab._tPos < first._tPos) return;      // already above them
      let target = first;
      while (target.group) target = target.group;   // before its split / folder, not into it
      gBrowser.moveTabBefore(tab, target);
    } catch (e) { log(e); }
  }

  function neighbour(dir) {
    const cur = current(), g = groupOf(cur);
    if (!g) return null;
    const P = panelSize();
    const rs = rects(g.layoutTree).map((r) => ({ tab: r.tab, x: r.x * P.w, y: r.y * P.h, w: r.w * P.w, h: r.h * P.h }));
    const a = rs.find((r) => r.tab === cur);
    if (!a) return null;
    const ov = (p, pl, q, ql) => Math.min(p + pl, q + ql) - Math.max(p, q);
    let best = null, score = Infinity;
    for (const b of rs) {
      if (b.tab === cur) continue;
      let gap, o;
      if (dir === "l") { if (b.x + b.w > a.x + 2) continue; gap = a.x - (b.x + b.w); o = ov(a.y, a.h, b.y, b.h); }
      if (dir === "r") { if (b.x < a.x + a.w - 2) continue; gap = b.x - (a.x + a.w); o = ov(a.y, a.h, b.y, b.h); }
      if (dir === "u") { if (b.y + b.h > a.y + 2) continue; gap = a.y - (b.y + b.h); o = ov(a.x, a.w, b.x, b.w); }
      if (dir === "d") { if (b.y < a.y + a.h - 2) continue; gap = b.y - (a.y + a.h); o = ov(a.x, a.w, b.x, b.w); }
      const s = gap + (o > 0 ? 0 : 100000) - recency(b.tab) / 1e15;
      if (s < score) { score = s; best = b.tab; }
    }
    return best ? { tab: best, group: g, from: cur } : null;
  }

  function focusDir(dir) {
    const n = neighbour(dir);
    if (!n) return false;
    gBrowser.selectedTab = n.tab;
    setTimeout(() => n.tab.linkedBrowser.focus(), 0);
    return true;
  }

  // Alt+Shift+arrows = Hyprland's dwindle movewindow: take the tile out, then
  // put it back as if it were a new window opened with the cursor just past
  // the tile's edge in that direction (that point picks the tile to split and
  // the half). At the edge of the view there is nowhere to go.
  function moveDir(dir) {
    const cur = current(), g = groupOf(cur);
    if (!g) return;
    const a = tilePx(g).find((r) => r.tab === cur);
    if (!a) return;
    const pt = {
      l: { x: a.x - 2, y: a.y + a.h / 2 }, r: { x: a.x + a.w + 2, y: a.y + a.h / 2 },
      u: { x: a.x + a.w / 2, y: a.y - 2 }, d: { x: a.x + a.w / 2, y: a.y + a.h + 2 },
    }[dir];
    if (!hit(tilePx(g).filter((r) => r.tab !== cur), pt)) return;
    const sp = S(), leaf = findLeaf(g.layoutTree, cur);
    sp.removeNode(leaf);
    const after = tilePx(g);                       // the others, re-flowed into the gap
    const t = hit(after, pt);
    if (!t) return;
    sp.splitIntoNode(findLeaf(g.layoutTree, t.tab), leaf, placeAt(t, pt), 0.5);
    relayout(g);
  }

  // Alt+Ctrl+arrows = resizeactive ±40 px: → / ↓ make the tile 40 px wider /
  // taller, ← / ↑ narrower / shorter, moving whichever of its edges has a
  // neighbour (the split around it that runs the right way).
  const RESIZE_PX = 40, MIN_PX = 120;
  function resizeDir(dir) {
    const cur = current(), g = groupOf(cur);
    let node = g && findLeaf(g.layoutTree, cur);
    if (!node) return;
    const axis = dir === "l" || dir === "r" ? "row" : "column";
    while (node.parent && node.parent.direction !== axis) node = node.parent;
    const p = node.parent;
    if (!p) return;
    const i = p.children.indexOf(node);
    const sib = p.children[i + 1] || p.children[i - 1];
    const box = boxOf(g.layoutTree, p), P = panelSize();
    if (!sib || !box) return;
    const px = axis === "row" ? box.w * P.w : box.h * P.h;
    const min = (MIN_PX / px) * 100;
    let d = ((dir === "r" || dir === "d" ? RESIZE_PX : -RESIZE_PX) / px) * 100;
    d = Math.max(min - node.sizeInParent, Math.min(sib.sizeInParent - min, d));
    if (Math.abs(d) < 0.01) return;
    node.sizeInParent += d;
    sib.sizeInParent -= d;
    relayout(g);
  }

  function toggleSplit() {
    const g = groupOf(current());
    const leaf = g && findLeaf(g.layoutTree, current());
    if (!leaf || !leaf.parent) return false;
    leaf.parent.direction = leaf.parent.direction === "row" ? "column" : "row";
    relayout(g);
    return true;
  }

  // An empty workspace you are not looking at is closed (workspace-stack.py's
  // rule), so the next empty one is the only one there ever is.
  function onTabSelect(e) {
    const prev = e.detail && e.detail.previousTab;
    if (!prev || prev === e.target || prev.hasAttribute("zen-empty-tab") || !isEmptyWs(prev)) return;
    setTimeout(() => {
      try {
        if (prev.isConnected && !prev.selected && !prev.closing && isEmptyWs(prev) && gBrowser.tabs.length > 1)
          gBrowser.removeTab(prev, { animate: false, skipSessionStore: true });
      } catch (err) { log(err); }
    }, 0);
  }

  // Closing a tile keeps you in its workspace, on the tile you used last there
  // (Hyprland focuses a window of the same workspace). Zen's own pick is the
  // most recently used tab anywhere — for a tile just moved in with
  // Alt+Shift+N that is the workspace it came from. Firefox asks
  // gBrowser._findTabToBlurTo() before it even fires TabClose, so answer there.
  // A lone tab closing is left to Zen.
  // Closing the very last tab closes the window straight away — no detour
  // through Zen's empty "new tab" first (it used to flash one up while the
  // window went) — and the next start is a fresh browser, not that tab
  // restored: browser.startup.page is set to the home page for that one start
  // and put back (rice.tiles.fresh-start) once the next window is up.
  function isLastTab(tab) {
    return !gBrowser.tabs.some((t) => t !== tab && !t.closing && !t.hasAttribute("zen-empty-tab") &&
      !t.hasAttribute("zen-glance-tab"));
  }
  function hookLastClose() {
    const orig = gBrowser.removeTab;
    if (typeof orig !== "function" || orig.riceTiles) return;
    const wrapped = function (aTab, aParams = {}) {
      try {
        if (aTab && !aParams.skipSessionStore && started && !aTab.hasAttribute("zen-empty-tab") &&
            isLastTab(aTab) && !window.closed) {
          let browsers = 0;
          for (const w of Services.wm.getEnumerator("navigator:browser")) if (!w.closed) browsers++;
          if (browsers <= 1 && !PrivateBrowsingUtils.isWindowPrivate(window)) {
            Services.prefs.setIntPref("browser.startup.page", 1);
            Services.prefs.setBoolPref("rice.tiles.fresh-start", true);
          }
          window.close();
          return;
        }
        // a tile you close (Ctrl+W, the tab's ×, middle click — the calls that
        // ask for animation) leaves with Hyprland's windowsOut: a still of it
        // shrinks and fades where it was while the others slide into the gap
        if (aTab && aParams.animate && !aParams.skipSessionStore && ANIM.on && !aTab._riceClosing && visibleTile(aTab)) {
          aTab._riceClosing = true;
          const box = containerOf(aTab), r = box.getBoundingClientRect();
          const self = this;
          stillOf(aTab).then((still) => {
            try { orig.call(self, aTab, aParams); } catch (e) { log(e); }
            playOut(still, r);
          });
          return;
        }
      } catch (e) { log(e); }
      return orig.call(this, aTab, aParams);
    };
    wrapped.riceTiles = true;
    gBrowser.removeTab = wrapped;
  }
  function freshStartDone() {
    if (!Services.prefs.getBoolPref("rice.tiles.fresh-start", false)) return;
    Services.prefs.clearUserPref("rice.tiles.fresh-start");
    Services.prefs.clearUserPref("browser.startup.page");
  }
  let started = false;
  setTimeout(() => { started = true; }, 1500);   // Zen tidies tabs at start-up; leave those alone

  function hookBlur() {
    const orig = gBrowser._findTabToBlurTo;
    if (typeof orig !== "function" || orig.riceTiles) return;
    const wrapped = function (aTab, aExcludeTabs = []) {
      try {
        const g = aTab && aTab.selected && groupOf(aTab);
        if (g) {
          const skip = new Set(aExcludeTabs);
          const others = g.tabs.filter((t) => t !== aTab && !skip.has(t) && usable(t));
          if (others.length) return others.reduce((a, b) => (recency(b) > recency(a) ? b : a));
        }
      } catch (e) { log(e); }
      return orig.call(this, aTab, aExcludeTabs);
    };
    wrapped.riceTiles = true;
    gBrowser._findTabToBlurTo = wrapped;
  }

  // Focus follows the mouse between the tiles of a split (Hyprland's
  // follow_mouse = 1): moving the cursor onto another tile selects it and
  // gives it the keyboard. Not while a button is held (dragging, selecting
  // text) or the picker is up, and not while you are TYPING in the browser's
  // own UI (URL bar, find bar, a sidebar search) — that would yank the text
  // away. Merely having the caret there doesn't count: Zen often starts with
  // the URL bar focused, which used to keep this off until the first click.
  let lastChromeKey = 0;
  function chromeEditable(a) {
    return !!a && a.localName !== "browser" && (a.isContentEditable || /^(input|textarea|select)$/i.test(a.localName) ||
      !!(a.closest && a.closest("#urlbar, findbar, .urlbar")));
  }
  function typingInChrome() {
    if (window.gURLBar && (gURLBar.view?.isOpen || (gURLBar.focused && gBrowser.userTypedValue))) return true;
    return chromeEditable(document.activeElement) && Date.now() - lastChromeKey < 2500;
  }
  // only keys that edit text count — not Ctrl+T, Alt+…, or a bare modifier
  // (those used to hold hover off for 2.5 s after every shortcut)
  function onAnyKey(e) {
    if (e.ctrlKey || e.altKey || e.metaKey) return;
    if (e.key.length !== 1 && !/^(Backspace|Delete|Enter)$/.test(e.key)) return;
    if (chromeEditable(document.activeElement)) lastChromeKey = Date.now();
  }

  function tileAt(e, g) {
    const box = e.target && e.target.closest && e.target.closest(".browserSidebarContainer");
    const b = box ? box.querySelector("browser") : e.target && e.target.localName === "browser" ? e.target : null;
    const t = b && gBrowser.getTabForBrowser(b);
    if (t) return t;
    // something drawn over the page (Zen's split overlay…): go by position
    for (const tab of g.tabs) {
      const c = tab.linkedBrowser && tab.linkedBrowser.closest(".browserSidebarContainer");
      const r = c && c.getBoundingClientRect();
      if (r && r.width && e.clientX >= r.left && e.clientX < r.right && e.clientY >= r.top && e.clientY < r.bottom) return tab;
    }
    return null;
  }

  function focusFollowsMouse(e) {
    try {
      if (e.buttons || P.open) return;
      const cur = current(), g = groupOf(cur);
      if (!g) return;
      const tab = tileAt(e, g);
      if (!tab || tab === cur || !g.tabs.includes(tab) || !usable(tab)) return;
      if (typingInChrome()) return;
      gBrowser.selectedTab = tab;
      tab.linkedBrowser.focus();
    } catch (err) { log(err); }
  }

  // ── animations: Hyprland's own (read from hyprland.conf's animations {}) ──
  //
  // Tiles move and resize with `windows` (FLIP: the new layout is applied at
  // once, then each tile is transformed from where it was back to where it
  // now is), a new tile pops in with `windowsIn` (popin N%) + `fadeIn`, and a
  // closed one leaves with `windowsOut` + `fadeOut`. Switching workspace isn't
  // animated here. Zen's own 90 ms inset transition is turned off (CSS below).

  const ANIM = (() => {
    const A = {
      on: true,
      move: { duration: 350, easing: "cubic-bezier(0.23, 1, 0.32, 1)" },
      inPop: { duration: 380, easing: "cubic-bezier(0.34, 1.32, 0.64, 1)", scale: 0.94 },
      inFade: { duration: 220, easing: "cubic-bezier(0.33, 1, 0.68, 1)" },
      outPop: { duration: 140, easing: "cubic-bezier(0.32, 0, 0.67, 0)", scale: 0.94 },
      outFade: { duration: 140, easing: "cubic-bezier(0.32, 0, 0.67, 0)" },
      wsIn: { duration: 130, easing: "cubic-bezier(0.5, 0.5, 0.75, 1)" },
      wsOut: { duration: 130, easing: "cubic-bezier(0.5, 0.5, 0.75, 1)" },
    };
    try {
      const f = Services.dirsvc.get("Home", Ci.nsIFile);
      for (const p of [".config", "hypr", "hyprland.conf"]) f.append(p);
      const text = Cu.readUTF8File(f).replace(/#.*$/gm, "");
      const block = /animations\s*\{([\s\S]*?)\n\}/.exec(text);
      if (!block) return A;
      const body = block[1];
      const en = /^\s*enabled\s*=\s*(\S+)/m.exec(body);
      if (en && /^(false|no|0|off)$/i.test(en[1])) { A.on = false; return A; }
      const bez = { default: [0, 0.75, 0.15, 1], linear: [0, 0, 1, 1] };
      for (const m of body.matchAll(/^\s*bezier\s*=\s*([^,\s]+)\s*,\s*([-\d.]+)\s*,\s*([-\d.]+)\s*,\s*([-\d.]+)\s*,\s*([-\d.]+)/gm))
        bez[m[1]] = [m[2], m[3], m[4], m[5]].map(Number);
      const an = {};
      for (const m of body.matchAll(/^\s*animation\s*=\s*([^,\s]+)\s*,\s*(\d)\s*(?:,\s*([\d.]+))?\s*(?:,\s*([^,\s]+))?\s*(?:,\s*(.+))?$/gm))
        an[m[1]] = { on: m[2] !== "0", speed: Number(m[3] || 0), curve: m[4], style: (m[5] || "").trim() };
      const pick = (...names) => names.map((n) => an[n]).find(Boolean);
      const conv = (a, base) => {
        if (!a) return base;
        const b = bez[a.curve] || bez.default;
        const out = { ...base, duration: a.on ? Math.round(a.speed * 100) : 0, easing: `cubic-bezier(${b.join(", ")})` };
        const pct = /popin\s+([\d.]+)%/.exec(a.style);
        if (pct) out.scale = Number(pct[1]) / 100;
        return out;
      };
      A.move = conv(pick("windowsMove", "windows", "global"), A.move);
      A.inPop = conv(pick("windowsIn", "windows", "global"), A.inPop);
      A.outPop = conv(pick("windowsOut", "windows", "global"), A.outPop);
      A.inFade = conv(pick("fadeIn", "fade", "global"), A.inFade);
      A.outFade = conv(pick("fadeOut", "fade", "global"), A.outFade);
      A.wsIn = conv(pick("workspacesIn", "workspaces", "global"), A.wsIn);
      A.wsOut = conv(pick("workspacesOut", "workspaces", "global"), A.wsOut);
    } catch (e) { log(e); }
    return A;
  })();

  const panelsEl = () => document.getElementById("tabbrowser-tabpanels");
  const containerOf = (tab) => tab.linkedBrowser && tab.linkedBrowser.closest(".browserSidebarContainer");

  // the tiles on screen now: the split's containers, or the one selected panel
  function shownBoxes() {
    const p = panelsEl();
    if (!p) return [];
    const split = p.getAttribute("zen-split-view") === "true";
    return [...p.children].filter((c) => c.classList.contains("browserSidebarContainer") &&
      (split ? c.getAttribute("zen-split") === "true" : c.classList.contains("deck-selected")));
  }

  function visibleTile(tab) {
    const p = panelsEl(), box = containerOf(tab);
    return !!(p && box && p.getAttribute("zen-split-view") === "true" && shownBoxes().includes(box));
  }

  // a box's place in the layout, ignoring any transform an animation adds
  function layoutRect(b) {
    const op = b.offsetParent, o = op ? op.getBoundingClientRect() : { left: 0, top: 0 };
    return { left: o.left + b.offsetLeft, top: o.top + b.offsetTop, width: b.offsetWidth, height: b.offsetHeight };
  }

  let layoutCache = new Map();                // box → its layout rect after the last change
  function remember() {
    layoutCache = new Map(shownBoxes().map((b) => [b, layoutRect(b)]));
  }

  function stopTileAnims(box) {
    for (const a of box.getAnimations()) if (a.id === "rice-tile") a.cancel();
  }

  function run(el, frames, opt) {
    if (!opt.duration) return null;
    const a = el.animate(frames, { duration: opt.duration, easing: opt.easing, fill: "none" });
    a.id = "rice-tile";
    return a;
  }

  function onLayout() {
    try {
      const p = panelsEl();
      if (!ANIM.on || !p || p.hasAttribute("zen-split-resizing") || p.hasAttribute("dragging-split")) return remember();
      const before = layoutCache;
      const now = shownBoxes();
      const rects = new Map(now.map((b) => [b, layoutRect(b)]));
      // the same workspace before and after (a tile stayed) — otherwise it's a
      // workspace switch, which isn't animated
      if (!now.some((b) => before.has(b))) {
        // a different workspace: fade it in
        if (before.size && ANIM.wsIn.duration)
          for (const b of now) { stopTileAnims(b); run(b, [{ opacity: 0 }, { opacity: 1 }], ANIM.wsIn); }
      } else {
        for (const b of now) {
          const n = rects.get(b);
          let o = before.get(b);
          if (!n.width || !n.height) continue;
          if (!o) {
            stopTileAnims(b);
            run(b, [{ transform: `scale(${ANIM.inPop.scale})` }, { transform: "none" }], ANIM.inPop);
            run(b, [{ opacity: 0 }, { opacity: 1 }], ANIM.inFade);
          } else if (Math.abs(o.left - n.left) + Math.abs(o.top - n.top) + Math.abs(o.width - n.width) + Math.abs(o.height - n.height) > 1) {
            // interrupted mid-move: start from where it is on screen right now
            const moving = b.getAnimations().some((a) => a.id === "rice-tile" && a.playState === "running");
            if (moving) {
              const v = b.getBoundingClientRect();
              stopTileAnims(b);
              if (v.width && v.height) o = { left: v.left, top: v.top, width: v.width, height: v.height };
            }
            run(b, [
              { transformOrigin: "0 0", transform: `translate(${o.left - n.left}px, ${o.top - n.top}px) scale(${o.width / n.width}, ${o.height / n.height})` },
              { transformOrigin: "0 0", transform: "none" },
            ], ANIM.move);
          }
        }
      }
      layoutCache = rects;
    } catch (e) { log(e); }
  }

  async function stillOf(tab, wait = 90) {
    try {
      const wg = tab.linkedBrowser.browsingContext?.currentWindowGlobal;
      if (!wg) return null;
      const bmp = await Promise.race([wg.drawSnapshot(null, 1, "white"), new Promise((r) => setTimeout(() => r(null), wait))]);
      if (!bmp) return null;
      const c = el("canvas", "rw-ghost-img");
      c.width = bmp.width;
      c.height = bmp.height;
      c.getContext("2d").drawImage(bmp, 0, 0);
      if (bmp.close) bmp.close();
      return c;
    } catch (e) { return null; }
  }

  function playOut(still, r, pop = ANIM.outPop, fade = ANIM.outFade) {
    try {
      if (!(pop && pop.duration) && !(fade && fade.duration)) return;
      const g = el("div", "rw-ghost", document.body);
      g.setAttribute("popover", "manual");
      Object.assign(g.style, { left: r.left + "px", top: r.top + "px", width: r.width + "px", height: r.height + "px" });
      if (still) g.appendChild(still);
      g.showPopover();
      const a = pop ? run(g, [{ transform: "none" }, { transform: `scale(${pop.scale})` }], pop) : null;
      const b = fade ? run(g, [{ opacity: 1 }, { opacity: 0 }], fade) : null;
      const end = Math.max(pop ? pop.duration : 0, fade ? fade.duration : 0);
      g.style.opacity = "0";
      setTimeout(() => g.remove(), end + 20);
      if (!a && !b) g.remove();
    } catch (e) { log(e); }
  }

  // Workspace switches fade like Hyprland's `workspaces … fade`: the new
  // workspace's tiles fade in (workspacesIn, in onLayout); when the switch is
  // ours (Alt+1…0, Alt+N, swipe, the picker) the old tiles are caught first
  // (≤50 ms) and fade out on top (workspacesOut) — a crossfade. Switching by
  // clicking the tab list gets the fade-in only.
  async function crossfade(doSwitch) {
    const before = ANIM.on && ANIM.wsOut.duration ? shownBoxes() : [];
    if (!before.length) return doSwitch();
    const rects = before.map(layoutRect);
    const stills = await Promise.all(before.map((b) => {
      const t = gBrowser.getTabForBrowser(b.querySelector("browser"));
      return t ? stillOf(t, 50) : null;
    }));
    doSwitch();
    if (shownBoxes().some((b) => before.includes(b))) return;     // stayed in the same workspace
    stills.forEach((st, i) => { if (st) playOut(st, rects[i], null, ANIM.wsOut); });
  }

  function setupAnimations() {
    const p = panelsEl();
    if (!p) return;
    new MutationObserver((records) => {
      if (records.some((r) => r.target === p || r.target.parentNode === p || r.type === "childList")) onLayout();
    }).observe(p, { childList: true, subtree: true, attributes: true,
                    attributeFilter: ["style", "zen-split", "is-zen-split", "zen-split-view", "class"] });
    new ResizeObserver(() => remember()).observe(p);
    remember();
  }

  // ── links: a tab a page opens joins that page's workspace ──
  //
  // Like a new window on the desktop: a tab opened from a page (target=_blank,
  // middle click, "Open Link in New Tab", window.open) becomes a tile next to
  // the tab it came from — on the cursor's side when the cursor is over that
  // tile — unless that workspace is full (MAX_TILES), then it stays a new
  // workspace. A background open (middle click) keeps your focus where it was.
  // Pinned / Essential openers are left alone (Ctrl+W resets a pinned tab
  // instead of closing it, which would strand the tiles), and so are Glance
  // previews.
  let ownTabs = 0;                        // tabs this script is making (not links)
  function onTabOpen(e) {
    const tab = e.target, opener = tab.openerTab;
    if (!started || ownTabs || !opener || opener === tab) return;
    setTimeout(() => linkTile(tab, opener), 0);
  }
  function linkTile(tab, opener) {
    try {
      if (!tab.isConnected || tab.closing || !usable(tab) || tab.pinned || tab.hasAttribute("zen-essential") ||
          tab.hasAttribute("glance-id") || groupOf(tab)) return;
      if (!usable(opener) || opener.pinned || opener.hasAttribute("zen-essential") || folded(opener)) return;
      const g = groupOf(opener);
      if (g && g.tabs.length >= S().MAX_TABS) return;          // full: a workspace of its own
      const fg = gBrowser.selectedTab === tab;
      const keep = fg ? null : gBrowser.selectedTab;
      const list = tilePx(g, opener), r = list.find((q) => q.tab === opener) || list[0];
      const under = hit(list, mouse);
      insertTile(opener, tab, placeAt(r, under && under.tab === opener ? mouse : null));
      gBrowser.selectedTab = keep && keep.isConnected ? keep : tab;
    } catch (err) { log(err); }
  }

  // ── Alt + drag: move a tile with the mouse (Hyprland's SUPER + left drag) ──
  //
  // Hold Alt, press on a tile of a split and drag: the tile follows the
  // cursor, and where you let go it is put back like a new window opened
  // there — the tile under the cursor (in the layout without the dragged one)
  // splits, side by side if wider than tall, on the cursor's half; an outline
  // shows that spot. Let go over nothing, or press Esc, and it slides home.
  // Only in a split: on a lone tab Alt+click stays Zen's Glance (link preview).
  let drag = null;
  let altHeld = false;           // tracked from the keys too: some touchpad drags report no modifiers
  function onAltKey(e) {
    if (e.key === "Alt") altHeld = e.type === "keydown";
  }
  function rectsWithout(node, skip, x = 0, y = 0, w = 1, h = 1, out = []) {
    if (!node) return out;
    if (!node.children) {
      if (node.tab !== skip) out.push({ tab: node.tab, x, y, w, h });
      return out;
    }
    const kids = node.children.filter((c) => c.children || c.tab !== skip);
    const size = (c) => c.sizeInParent || 100 / node.children.length;
    const total = kids.reduce((a, c) => a + size(c), 0) || 1;
    let off = 0;
    for (const c of kids) {
      const f = size(c) / total;
      if (node.direction === "row") rectsWithout(c, skip, x + off * w, y, f * w, h, out);
      else rectsWithout(c, skip, x, y + off * h, w, f * h, out);
      off += f;
    }
    return out;
  }
  function dropSpot(d, pt) {
    const p = panelRect();
    const list = rectsWithout(d.g.layoutTree, d.tab).filter((r) => r.w > 0 && r.h > 0)
      .map((r) => ({ tab: r.tab, x: p.x + r.x * p.w, y: p.y + r.y * p.h, w: r.w * p.w, h: r.h * p.h }));
    const t = hit(list, pt);
    return t ? { target: t, side: placeAt(t, pt) } : null;
  }
  function flipFrom(box, from) {
    const n = layoutRect(box);
    stopTileAnims(box);
    if (!n.width || !n.height) return;
    run(box, [
      { transformOrigin: "0 0", transform: `translate(${from.left - n.left}px, ${from.top - n.top}px) scale(${from.width / n.width}, ${from.height / n.height})` },
      { transformOrigin: "0 0", transform: "none" },
    ], ANIM.move);
    layoutCache.set(box, n);
  }
  function onMouseDown(e) {
    try {
      if (e.button !== 0 || !(e.altKey || altHeld) || e.ctrlKey || e.metaKey || e.shiftKey || P.open || drag) return;
      const cur = current(), g = groupOf(cur);
      if (!g) return;
      const tab = tileAt(e, g);
      if (!tab || !g.tabs.includes(tab)) return;
      e.preventDefault();
      e.stopPropagation();
      e.stopImmediatePropagation();
      const box = containerOf(tab);
      stopTileAnims(box);
      if (gBrowser.selectedTab !== tab) gBrowser.selectedTab = tab;
      const ov = el("div", "rw-drag", document.body);
      ov.setAttribute("popover", "manual");
      const spot = el("div", "rw-drop", ov);
      spot.hidden = true;
      drag = { tab, g, box, ov, spot, x0: e.clientX, y0: e.clientY, moved: false };
      Object.assign(box.style, { zIndex: "5", opacity: "0.9", pointerEvents: "none" });
      ov.addEventListener("mousemove", onDragMove);
      ov.addEventListener("mouseup", onDragUp);
      ov.addEventListener("contextmenu", (ev) => ev.preventDefault());
      ov.showPopover();
    } catch (err) { log(err); }
  }
  function onDragMove(e) {
    if (!drag) return;
    const dx = e.clientX - drag.x0, dy = e.clientY - drag.y0;
    if (Math.abs(dx) + Math.abs(dy) > 3) drag.moved = true;
    drag.box.style.transform = `translate(${dx}px, ${dy}px)`;
    const s = drag.moved && dropSpot(drag, { x: e.clientX, y: e.clientY });
    if (!s) { drag.spot.hidden = true; return; }
    // the tiles sit inside Zen's split gaps (their margins)
    const cs = getComputedStyle(drag.box), mt = parseFloat(cs.marginTop) || 0, mr = parseFloat(cs.marginRight) || 0;
    const r = { x: s.target.x, y: s.target.y + mt, w: s.target.w - mr, h: s.target.h - mt }, half = { ...r };
    if (s.side === "left" || s.side === "right") { half.w = r.w / 2; if (s.side === "right") half.x = r.x + r.w / 2; }
    else { half.h = r.h / 2; if (s.side === "bottom") half.y = r.y + r.h / 2; }
    Object.assign(drag.spot.style, { left: half.x + "px", top: half.y + "px", width: half.w + "px", height: half.h + "px" });
    drag.spot.hidden = false;
  }
  function endDrag(pt) {
    const d = drag;
    if (!d) return;
    drag = null;
    try {
      const from = d.box.getBoundingClientRect();
      Object.assign(d.box.style, { zIndex: "", opacity: "", pointerEvents: "", transform: "" });
      try { d.ov.hidePopover(); } catch (e) {}
      d.ov.remove();
      const s = pt && d.moved && groupOf(d.tab) === d.g ? dropSpot(d, pt) : null;
      if (s) {
        const sp = S(), leaf = findLeaf(d.g.layoutTree, d.tab);
        sp.removeNode(leaf);
        const t = hit(tilePx(d.g), pt) || s.target;
        layoutCache.set(d.box, { left: from.left, top: from.top, width: from.width, height: from.height });
        sp.splitIntoNode(findLeaf(d.g.layoutTree, t.tab), leaf, placeAt(t, pt), 0.5);
        relayout(d.g);
      } else {
        flipFrom(d.box, from);                    // back home
      }
      d.tab.linkedBrowser.focus();
    } catch (err) { log(err); }
  }
  function onDragUp(e) {
    endDrag({ x: e.clientX, y: e.clientY });
  }

  // ── toast ────────────────────────────────────────────────────────────────

  let toastEl = null, toastTimer = null;
  function toast(text) {
    if (!toastEl) {
      toastEl = el("div", "rw-toast", document.body);
      toastEl.setAttribute("popover", "manual");
    }
    toastEl.textContent = text;
    try { toastEl.showPopover(); } catch (e) {}
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { try { toastEl.hidePopover(); } catch (e) {} }, 1800);
  }

  // ── thumbnails ───────────────────────────────────────────────────────────

  const shots = new WeakMap();      // tab → canvas

  async function snap(tab) {
    try {
      const b = tab.linkedBrowser;
      const wg = b && b.browsingContext && b.browsingContext.currentWindowGlobal;
      if (!wg || tab.hasAttribute("pending")) return shots.get(tab) || null;
      const P = panelSize();
      const scale = Math.min(1, 720 / Math.max(1, b.clientWidth || P.w));
      const bmp = await Promise.race([
        wg.drawSnapshot(null, scale, "white"),
        new Promise((r) => setTimeout(() => r(null), 1500)),
      ]);
      if (!bmp) return shots.get(tab) || null;
      const c = el("canvas", "rw-img");
      c.width = bmp.width;
      c.height = bmp.height;
      c.getContext("2d").drawImage(bmp, 0, 0);
      if (bmp.close) bmp.close();
      shots.set(tab, c);
      return c;
    } catch (e) {
      return shots.get(tab) || null;
    }
  }

  function host(tab) {
    try {
      const u = tab.linkedBrowser.currentURI;
      if (NEWTAB.has(u.spec)) return "new tab";
      let h = "";
      try { h = u.host; } catch (e) {}
      if (h) return h.replace(/^www\./, "");
      if (u.schemeIs("file")) return decodeURIComponent(u.spec.split(/[?#]/)[0].split("/").pop());
      return u.scheme + ":";
    } catch (e) { return ""; }
  }

  // ── the picker ───────────────────────────────────────────────────────────

  const P = {
    open: false, cards: [], all: [], pos: 0, target: 0, raf: 0,
    alt: false, cycled: false, carry: false, searching: false, query: "", wheel: 0,
    root: null, band: null, bar: null, cap: null,
  };

  function geometry() {
    const H = window.innerHeight, W = window.innerWidth;
    const ch = Math.round(H * 0.34);
    return { W, H, ch, slant: Math.round(ch * 0.3), wc: Math.round(ch * 1.55), wsl: Math.round(ch * 0.3),
             gap: 12, cy: Math.round(H / 2 - ch / 2 + 24) };
  }

  function collect() {
    const cur = current();
    const us = units();
    const all = [];
    us.forEach((u, i) => {
      if (u.empty && !u.current) return;
      all.push({ unit: u, current: u.current, empty: u.empty, num: i < 10 ? String((i + 1) % 10) : "" });
    });
    if (!all.some((c) => c.empty)) {
      // the one empty workspace: where you already are (Zen's hidden empty tab), or the next one
      const here = cur.hasAttribute("zen-empty-tab");
      all.push({ unit: null, current: here, empty: true, num: "+" });
    }
    for (const c of all) {
      if (!c.unit) { c.title = "New workspace"; c.sub = "an empty page — search to fill it"; continue; }
      const u = c.unit;
      c.title = u.empty ? "New workspace" : u.focus.label;
      const hosts = [...new Set(u.tabs.map(host).filter(Boolean))];
      c.sub = u.empty ? "an empty page — search to fill it"
        : [u.tabs.length > 1 ? `${u.tabs.length} tiles` : "", ...hosts].filter(Boolean).join(" · ");
      c.hay = u.tabs.map((t) => `${t.label} ${host(t)} ${t.linkedBrowser?.currentURI?.spec || ""}`).join(" ").toLowerCase();
    }
    P.all = all;
  }

  function buildMini(card) {
    const g = geometry();
    const shot = el("div", "rw-shot");
    shot.style.width = g.wc + g.slant + "px";
    shot.style.height = g.ch + "px";
    if (card.empty) {
      el("div", "rw-plus", shot, "\u{f0415}");
      return shot;
    }
    const u = card.unit;
    const tiles = u.group ? rects(u.group.layoutTree).filter((r) => u.tabs.includes(r.tab))
      : [{ tab: u.tabs[0], x: 0, y: 0, w: 1, h: 1 }];
    const pad = 5;
    for (const r of tiles) {
      const t = el("div", "rw-tile", shot);
      t.style.left = `calc(${r.x * 100}% + ${pad}px)`;
      t.style.top = `calc(${r.y * 100}% + ${pad}px)`;
      t.style.width = `calc(${r.w * 100}% - ${pad * 2}px)`;
      t.style.height = `calc(${r.h * 100}% - ${pad * 2}px)`;
      if (u.tabs.length > 1 && r.tab === u.focus) t.classList.add("focused");
      const fill = (c) => {
        t.textContent = "";
        if (c) { t.appendChild(c); return; }
        const icon = r.tab.getAttribute("image");
        if (icon) {
          const i = el("img", "rw-icon", t);
          i.src = icon;
        } else el("div", "rw-glyph", t, "\u{f059f}");
        el("div", "rw-tlabel", t, r.tab.label);
      };
      fill(shots.get(r.tab) || null);
      if (P.fresh.has(r.tab)) continue;
      P.fresh.add(r.tab);
      snap(r.tab).then((c) => { if (P.open && c && t.isConnected) fill(c); });
    }
    return shot;
  }

  function build() {
    const g = geometry();
    const q = P.query.toLowerCase();
    P.cards = P.all.filter((c) => !q || c.current || (c.hay && c.hay.includes(q)));
    P.band.textContent = "";
    P.root.style.setProperty("--s", g.slant + "px");
    P.cards.forEach((c, i) => {
      const card = el("div", "rw-card", P.band);
      card.style.top = g.cy + "px";
      card.style.height = g.ch + "px";
      if (c.current) card.classList.add("current");
      el("div", "rw-edge", card);
      const face = el("div", "rw-face", card);
      face.appendChild(buildMini(c));
      el("div", "rw-dim", face);
      const badge = el("div", "rw-badge", card, c.num || (c.current ? "\u{f0765}" : ""));
      if (c.current) badge.classList.add("current");
      card.addEventListener("mousedown", (e) => {
        e.stopPropagation();
        if (e.button !== 0) return;
        if (i === P.target) apply(false);
        else select(i);
      });
      c.el = card;
    });
    // toolbar dots
    P.dots.textContent = "";
    P.cards.forEach((c, i) => {
      const d = el("div", "rw-dot", P.dots, c.num || "\u{f0765}");
      if (c.current) d.classList.add("current");
      if (c.empty && !c.current) d.classList.add("empty");
      d.addEventListener("mousedown", (e) => { e.stopPropagation(); select(i); });
      c.dot = d;
    });
    P.target = Math.max(0, Math.min(P.target, P.cards.length - 1));
  }

  function render() {
    const g = geometry(), n = P.cards.length;
    const widths = [], lefts = [];
    let x = 0;
    for (let i = 0; i < n; i++) {
      const w = g.wsl + (g.wc - g.wsl) * (1 - Math.min(1, Math.abs(i - P.pos)));
      lefts.push(x);
      widths.push(w);
      x += w + g.gap;
    }
    if (n) {
      const f = Math.max(0, Math.min(n - 1, Math.floor(P.pos))), f1 = Math.min(f + 1, n - 1), frac = P.pos - f;
      const c0 = lefts[f] + widths[f] / 2, c1 = lefts[f1] + widths[f1] / 2;
      const off = g.W / 2 - g.slant / 2 - (c0 + (c1 - c0) * frac);
      P.cards.forEach((c, i) => {
        const w = widths[i] + g.slant;
        c.el.style.left = off + lefts[i] + "px";
        c.el.style.width = w + "px";
        c.el.querySelector(".rw-shot").style.left = (w - (g.wc + g.slant)) / 2 - 2 + "px";
        const on = i === P.target;
        c.el.classList.toggle("selected", on);
        c.dot.classList.toggle("selected", on);
        c.el.querySelector(".rw-dim").style.opacity = String(0.55 * Math.min(1, Math.abs(i - P.pos)));
      });
    }
    // toolbar + caption
    const top = g.cy, bottom = g.cy + g.ch;
    P.bar.style.bottom = g.H - top + 30 + "px";
    P.cap.style.top = bottom + 26 + "px";
    P.label.textContent = P.searching ? "/" + P.query + "▏" : P.carry ? "\u{f0dad} carry tile" : "\u{f0570} Workspaces";
    P.label.classList.toggle("search", P.searching);
    const c = P.cards[P.target];
    P.title.textContent = c ? c.title : `No workspace matches “${P.query}”`;
    P.sub.textContent = c ? (P.carry ? "carry the focused tile here — " : "") + c.sub : "";
    P.count.textContent = n ? `${P.target + 1} / ${n}` : "";
  }

  function tick() {
    const d = P.target - P.pos;
    P.pos = Math.abs(d) < 0.002 ? P.target : P.pos + d * 0.28;
    render();
    P.raf = P.pos !== P.target ? requestAnimationFrame(tick) : 0;
  }

  function kick() {
    if (!P.raf) P.raf = requestAnimationFrame(tick);
  }

  function select(i) {
    if (!P.cards.length) return;
    P.target = Math.max(0, Math.min(P.cards.length - 1, i));
    kick();
  }

  function move(dir, wrap) {
    const n = P.cards.length;
    if (!n) return;
    select(wrap ? (P.target + dir + n) % n : P.target + dir);
  }

  function ensureRoot() {
    if (P.root) return;
    const root = el("div", "", document.body);
    root.id = "rice-wsp";
    root.setAttribute("popover", "manual");
    root.tabIndex = -1;
    P.band = el("div", "rw-band", root);
    P.bar = el("div", "rw-bar", root);
    P.label = el("div", "rw-label", P.bar);
    el("div", "rw-sep", P.bar);
    P.dots = el("div", "rw-dots", P.bar);
    el("div", "rw-sep", P.bar);
    el("div", "rw-hint", P.bar, "↹ move · ⏎ go · m carry · x close · / search");
    P.cap = el("div", "rw-cap", root);
    P.title = el("div", "rw-title", P.cap);
    P.sub = el("div", "rw-sub", P.cap);
    P.count = el("div", "rw-count", P.cap);
    root.addEventListener("mousedown", (e) => { if (e.button === 0) closePicker(); });
    root.addEventListener("contextmenu", (e) => { e.preventDefault(); closePicker(); });
    root.addEventListener("wheel", (e) => {
      e.preventDefault();
      P.wheel += e.deltaMode ? e.deltaY * 40 : e.deltaY;
      while (Math.abs(P.wheel) >= 60) {
        move(P.wheel > 0 ? 1 : -1, false);
        P.wheel -= Math.sign(P.wheel) * 60;
      }
    }, { passive: false });
    P.root = root;
  }

  function openPicker(fromAlt) {
    ensureRoot();
    P.fresh = new Set();
    P.query = "";
    P.searching = false;
    P.carry = false;
    P.alt = !!fromAlt;
    P.cycled = false;
    collect();
    build();
    P.target = Math.max(0, P.cards.findIndex((c) => c.current));   // where you are, like SUPER+Tab
    P.pos = P.target;
    P.open = true;
    try { P.root.showPopover(); } catch (e) { log(e); }
    P.root.focus();
    render();
    requestAnimationFrame(() => P.root.classList.add("shown"));
  }

  function closePicker() {
    if (!P.open) return;
    P.open = false;
    P.root.classList.remove("shown");
    cancelAnimationFrame(P.raf);
    P.raf = 0;
    try { P.root.hidePopover(); } catch (e) {}
    P.band.textContent = "";
    try { gBrowser.selectedBrowser.focus(); } catch (e) {}
  }

  function apply(carryNow) {
    const c = P.cards[P.target];
    const carry = P.carry || carryNow;
    closePicker();
    if (!c) return;
    const dest = c.unit ? c.unit : "new";
    if (carry) moveTile(dest);
    else go(dest);
  }

  function closeSelected() {
    const c = P.cards[P.target];
    if (!c || !c.unit) return;
    const tabs = c.unit.tabs.slice();
    if (tabs.length >= gBrowser.visibleTabs.length) return toast("That is the last workspace");
    gBrowser.removeTabs(tabs);
    setTimeout(() => {
      if (!P.open) return;
      collect();
      build();
      P.pos = P.target;
      render();
    }, 50);
  }

  // while searching: the first match that isn't where you already are
  function firstMatch() {
    const i = P.cards.findIndex((c) => !c.current);
    select(P.query && i >= 0 ? i : 0);
    render();
  }

  function pickerKey(e) {
    const k = e.key;
    const eat = () => { e.preventDefault(); e.stopPropagation(); e.stopImmediatePropagation(); };
    eat();
    if (e.repeat && k === "Alt") return;
    if (k === "Tab") { move(e.shiftKey ? -1 : 1, true); if (e.altKey) P.cycled = true; return; }
    if (P.searching) {
      if (k === "Escape") { P.searching = false; P.query = ""; build(); select(0); return; }
      if (k === "Enter") return apply(e.shiftKey);
      if (k === "Backspace") { P.query = P.query.slice(0, -1); build(); firstMatch(); return; }
      if (k === "ArrowLeft") return move(-1);
      if (k === "ArrowRight") return move(1);
      if (k.length === 1 && !e.ctrlKey && !e.altKey) { P.query += k; build(); firstMatch(); return; }
      return render();
    }
    if (k === "Escape" || k === "q") return closePicker();
    if (k === "Enter" || k === " ") return apply(e.shiftKey);
    if (k === "ArrowLeft" || k === "h") return move(-1);
    if (k === "ArrowRight" || k === "l") return move(1);
    if (k === "Home") return select(0);
    if (k === "End") return select(P.cards.length - 1);
    if (k === "m") { P.carry = !P.carry; return render(); }
    if (k === "x" || k === "Delete") return closeSelected();
    if (k === "/") { P.searching = true; return render(); }
    const m = /^Digit([0-9])$/.exec(e.code);
    if (m) {
      const want = m[1];
      const i = P.cards.findIndex((c) => c.num === want);
      if (i >= 0) select(i);
    }
  }

  // ── keys ─────────────────────────────────────────────────────────────────

  function onKeyDown(e) {
    try {
      if (drag) {
        if (e.key === "Escape") { endDrag(null); e.preventDefault(); e.stopPropagation(); }
        return;
      }
      if (P.open) return pickerKey(e);
      const alt = e.altKey && !e.ctrlKey && !e.metaKey;
      const ctrl = e.ctrlKey && !e.altKey && !e.metaKey;
      const ctrlAlt = e.ctrlKey && e.altKey && !e.metaKey && !e.shiftKey;
      const ARROW = { ArrowLeft: "l", ArrowRight: "r", ArrowUp: "u", ArrowDown: "d" };
      // the arrow keys only belong to the tiles inside a split view; on a lone
      // tab Ctrl+Alt+←/→ stay Zen's space switch
      const inSplit = () => !!groupOf(current());
      let done = false;
      if (alt && e.code === "Tab" && !e.shiftKey) { openPicker(true); done = true; }
      else if (alt && /^Digit[0-9]$/.test(e.code)) {
        const n = (Number(e.code.slice(5)) + 9) % 10;       // 1→0 … 9→8, 0→9
        const u = units()[n];
        // past the last workspace = a new one at the bottom (workspace-stack.py:
        // moving to an empty number lands on the next free one)
        if (e.shiftKey) moveTile(u || "new");
        else if (u) go(u);
        done = true;
      }
      else if (alt && !e.shiftKey && e.code === "KeyN") { crossfade(() => newWorkspace()); done = true; }
      else if (alt && (e.code === "PageDown" || e.code === "PageUp")) { step(e.code === "PageDown" ? 1 : -1); done = true; }
      else if (alt && !e.shiftKey && e.code === "KeyT") done = toggleSplit();
      else if (alt && !e.shiftKey && ({ KeyH: "l", KeyJ: "d", KeyK: "u", KeyL: "r" })[e.code])
        done = focusDir({ KeyH: "l", KeyJ: "d", KeyK: "u", KeyL: "r" }[e.code]);
      else if (alt && !e.shiftKey && ARROW[e.code] && inSplit()) { focusDir(ARROW[e.code]); done = true; }
      else if (alt && e.shiftKey && ARROW[e.code] && inSplit()) { moveDir(ARROW[e.code]); done = true; }
      else if (ctrlAlt && ARROW[e.code] && inSplit()) { resizeDir(ARROW[e.code]); done = true; }
      else if (ctrl && !e.shiftKey && e.code === "KeyT") { tileNew(); done = true; }
      else if (ctrl && e.code === "Tab") { cycleTile(e.shiftKey ? -1 : 1); done = true; }
      else if (ctrl && !e.shiftKey && (e.code === "ArrowLeft" || e.code === "ArrowRight"))
        done = historyKey(e.code === "ArrowLeft" ? -1 : 1);
      if (done) {
        e.preventDefault();
        e.stopPropagation();
        e.stopImmediatePropagation();
      }
    } catch (err) { log(err); }
  }

  // Ctrl+←/→ = back / forward. With the chrome focused the goBackKb/goForwardKb
  // <key>s (customKeys.json) do it and the URL bar keeps its word jump; a page
  // eats Ctrl+←/→ itself (cmd_wordPrevious, even off a text field), so for a
  // focused page it is done here — unless a text field / editor in it has focus
  // (the widget's IME state follows the page's focused editable) or caret
  // browsing (F7) is on.
  function historyKey(dir) {
    const f = Services.focus.focusedElement;
    if (!f || f.localName !== "browser") return false;
    if (window.windowUtils.IMEStatus !== Ci.nsIDOMWindowUtils.IME_STATUS_DISABLED) return false;
    if (Services.prefs.getBoolPref("accessibility.browsewithcaret", false)) return false;
    document.getElementById(dir < 0 ? "Browser:Back" : "Browser:Forward")?.doCommand();
    return true;
  }

  function onKeyUp(e) {
    if (P.open && e.key === "Alt" && P.alt) {
      P.alt = false;
      if (P.cycled) apply(false);
    }
  }

  // ── style ────────────────────────────────────────────────────────────────

  function font() {
    try {
      const f = Services.dirsvc.get("Home", Ci.nsIFile);
      for (const p of [".config", "hypr", "theme", "font-shell"]) f.append(p);
      const v = f.exists() ? Cu.readUTF8File(f).trim() : "";
      if (v) return v;
    } catch (e) {}
    return "AdwaitaMono Nerd Font";
  }

  const CSS = `
#rice-wsp {
  --a: var(--rice-accent, #89b4fa); --crust: var(--rice-crust, #11111b); --mantle: var(--rice-mantle, #181825);
  --base: var(--rice-base, #1e1e2e); --s0: var(--rice-surface0, #313244); --s1: var(--rice-surface1, #45475a);
  --o0: var(--rice-overlay0, #6c7086); --sub: var(--rice-subtext0, #a6adc8); --text: var(--rice-text, #cdd6f4);
  --poly: polygon(var(--s) 0, 100% 0, calc(100% - var(--s)) 100%, 0 100%);
  position: fixed; inset: 0; width: 100vw; height: 100vh; max-width: none; max-height: none;
  margin: 0; padding: 0; border: 0; overflow: hidden; outline: none;
  background: color-mix(in srgb, var(--crust) 45%, transparent);
  color: var(--text); font-family: "${font()}", monospace; font-size: 11pt;
  opacity: 0; transition: opacity 140ms ease-out; user-select: none; -moz-user-focus: normal;
}
#rice-wsp.shown { opacity: 1; }
#rice-wsp .rw-card { position: absolute; cursor: pointer; filter: drop-shadow(0 10px 16px rgba(0,0,0,.45)); }
#rice-wsp .rw-edge { position: absolute; inset: 0; clip-path: var(--poly); background: color-mix(in srgb, var(--s1) 80%, transparent); }
#rice-wsp .rw-card.selected .rw-edge { background: var(--a); }
#rice-wsp .rw-face { position: absolute; inset: 2px; clip-path: var(--poly); background: var(--base); overflow: hidden; }
#rice-wsp .rw-card.selected .rw-face { inset: 3px; }
#rice-wsp .rw-dim { position: absolute; inset: 0; background: var(--crust); pointer-events: none; }
#rice-wsp .rw-shot { position: absolute; top: 0; background: var(--mantle); }
#rice-wsp .rw-tile { position: absolute; overflow: hidden; border-radius: 7px; background: var(--s0);
  display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 8px;
  outline: 1px solid color-mix(in srgb, var(--s1) 80%, transparent); }
#rice-wsp .rw-tile.focused { outline: 2px solid var(--a); }
#rice-wsp .rw-img { width: 100%; height: 100%; object-fit: cover; object-position: top; display: block; }
#rice-wsp .rw-icon { width: 34px; height: 34px; }
#rice-wsp .rw-glyph { font-size: 26pt; color: var(--o0); }
#rice-wsp .rw-tlabel { max-width: 85%; font-size: 9pt; color: var(--sub); overflow: hidden; white-space: nowrap; text-overflow: ellipsis; }
#rice-wsp .rw-plus { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center;
  font-size: 30pt; color: color-mix(in srgb, var(--text) 85%, transparent); background: var(--s0); }
#rice-wsp .rw-badge { position: absolute; top: 10px; left: calc(var(--s) * 0.9 + 6px); min-width: 26px; height: 26px;
  border-radius: 13px; display: flex; align-items: center; justify-content: center; padding: 0 6px; box-sizing: border-box;
  background: color-mix(in srgb, var(--crust) 75%, transparent); color: var(--text); font-size: 9pt; font-weight: bold; }
#rice-wsp .rw-badge.current { background: var(--a); color: var(--crust); }
#rice-wsp .rw-bar { position: absolute; left: 50%; transform: translateX(-50%); height: 44px; display: flex; align-items: center;
  gap: 10px; padding: 0 16px; border-radius: 22px; box-sizing: border-box; white-space: nowrap;
  background: color-mix(in srgb, var(--crust) 92%, transparent); border: 1px solid color-mix(in srgb, var(--s1) 90%, transparent); }
#rice-wsp .rw-label { color: var(--a); font-weight: bold; }
#rice-wsp .rw-label.search { color: var(--text); }
#rice-wsp .rw-sep { width: 1px; height: 20px; background: var(--s1); }
#rice-wsp .rw-dots { display: flex; gap: 6px; align-items: center; }
#rice-wsp .rw-dot { min-width: 20px; height: 20px; border-radius: 10px; display: flex; align-items: center; justify-content: center;
  box-sizing: border-box; padding: 0 4px; font-size: 7pt; font-weight: bold; cursor: pointer;
  background: var(--s1); color: var(--text); border: 1px solid var(--o0); }
#rice-wsp .rw-dot.current { background: var(--a); color: var(--crust); border-color: var(--a); }
#rice-wsp .rw-dot.empty { background: transparent; }
#rice-wsp .rw-dot.selected { box-shadow: 0 0 0 2px var(--crust), 0 0 0 3.5px color-mix(in srgb, var(--text) 90%, transparent); }
#rice-wsp .rw-hint { color: var(--o0); font-size: 9pt; }
#rice-wsp .rw-cap { position: absolute; left: 50%; transform: translateX(-50%); max-width: 70vw; padding: 9px 20px; border-radius: 16px;
  text-align: center; background: color-mix(in srgb, var(--crust) 88%, transparent); }
#rice-wsp .rw-title { font-weight: bold; overflow: hidden; white-space: nowrap; text-overflow: ellipsis; }
#rice-wsp .rw-sub { color: var(--a); font-size: 9pt; margin-top: 2px; overflow: hidden; white-space: nowrap; text-overflow: ellipsis; }
#rice-wsp .rw-count { color: var(--o0); font-size: 9pt; margin-top: 2px; }
#tabbrowser-tabpanels#tabbrowser-tabpanels[zen-split-view="true"] > .browserSidebarContainer[zen-split="true"] {
  transition: none !important;
}
.rw-drag { position: fixed; inset: 0; width: 100vw; height: 100vh; max-width: none; max-height: none;
  margin: 0; padding: 0; border: 0; background: transparent; cursor: grabbing; }
.rw-drop { position: fixed; box-sizing: border-box; border-radius: var(--zen-native-inner-radius, 8px);
  border: 2px solid var(--rice-accent, #89b4fa); background: color-mix(in srgb, var(--rice-accent, #89b4fa) 14%, transparent); }
.rw-ghost { position: fixed; inset: auto; margin: 0; padding: 0; border: 0; overflow: hidden; pointer-events: none;
  border-radius: var(--zen-native-inner-radius, 8px); background: var(--rice-base, #1e1e2e); }
.rw-ghost-img { width: 100%; height: 100%; display: block; }
.rw-toast { position: fixed; inset: auto; bottom: 48px; left: 50%; transform: translateX(-50%); margin: 0;
  padding: 8px 18px; border-radius: 16px; border: 1px solid var(--rice-surface1, #45475a);
  background: color-mix(in srgb, var(--rice-crust, #11111b) 92%, transparent); color: var(--rice-text, #cdd6f4);
  font-family: "${font()}", monospace; font-size: 10pt; }
`;

  // ── start ────────────────────────────────────────────────────────────────

  try {
    window.windowUtils.loadSheetUsingURIString(
      "data:text/css;charset=utf-8," + encodeURIComponent(CSS), window.windowUtils.AUTHOR_SHEET);
    if (S() && S().MAX_TABS < MAX_TILES) S().MAX_TABS = MAX_TILES;
    window.addEventListener("keydown", onKeyDown, true);
    window.addEventListener("keydown", onAnyKey, true);
    window.addEventListener("keyup", onKeyUp, true);
    window.addEventListener("TabSelect", onTabSelect);
    window.addEventListener("TabOpen", onTabOpen);
    window.addEventListener("mousedown", onMouseDown, true);
    window.addEventListener("keydown", onAltKey, true);
    window.addEventListener("keyup", onAltKey, true);
    hookBlur();
    hookLastClose();
    setupAnimations();
    freshStartDone();
    // starting up: land on the most recent workspace, not a new tab
    watchStartup();
    // chrome sees the pointer over web pages too (the parent process handles it first)
    window.addEventListener("mousemove", (e) => {
      mouse = { x: e.clientX, y: e.clientY };
      focusFollowsMouse(e);
    }, true);
    document.documentElement.addEventListener("mouseleave", () => { mouse = null; });
    // the window losing focus (not just focus moving into a page: that fires
    // "blur" on the window too, which used to close things mid-use)
    window.addEventListener("deactivate", () => { closePicker(); endDrag(null); altHeld = false; });
    window.addEventListener("resize", () => { if (P.open) { build(); render(); } });
    window.riceTiles = { ANIM_DEBUG: () => ANIM, units, mostRecent, cycleTile, landOnRecent, tileNew, newWorkspace, moveTile, step, focusDir, moveDir, resizeDir,
                         toggleSplit, openPicker, closePicker, isEmptyWs, P, get mouse() { return mouse; }, get altHeld() { return altHeld; }, get drag() { return drag; } };
  } catch (e) {
    log(e);
  }
})();
