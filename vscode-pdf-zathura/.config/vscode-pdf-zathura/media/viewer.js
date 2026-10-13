// The webview half: pdf.js renders, this file makes it behave like zathura —
// zathura's default keymap plus `map`/`unmap` from zathurarc, counts, the
// statusbar and inputbar, / ? n N search, f/F/c link hints, the Tab index,
// marks, the jumplist, and Ctrl+R recolouring with zathura's colours.
const vscode = acquireVsCodeApi();

// ── Keys are claimed first ──────────────────────────────────────────────
// VS Code's webview shell listens for keydown on this same window (bubble
// phase) and forwards every key to the workbench, so Ctrl+D, Ctrl+F, Ctrl+B,
// Ctrl+R... would hit VS Code commands as well. A capture-phase listener on
// the window runs before that one and stopPropagation keeps it from seeing
// the keys zathura uses. Registered before any await so nothing slips past
// while pdf.js loads. Keys that are not bound fall through, so Ctrl+P,
// Ctrl+W, Ctrl+Tab and friends still work.
//   'consume' = ours, 'isolate' = let the browser type it but keep it from
//   VS Code, 'pass' = not ours.
let onKey = () => 'pass';
window.addEventListener('keydown', e => {
    const r = onKey(e);
    if (r === 'pass') return;
    e.stopPropagation();
    if (r === 'consume') e.preventDefault();
}, true);

const R = JSON.parse(document.body.dataset.resources);
const $ = id => document.getElementById(id);
const root = document.documentElement.style;
const body = document.body;
const container = $('viewerContainer');
const viewerEl = $('viewer');
const hintsEl = $('hints');
const indexEl = $('index');
const inputbar = $('inputbar');
const promptEl = $('prompt');
const input = $('input');
const statusbar = $('statusbar');

const pdfjsLib = await import(R.pdf);
const pdfjsViewer = await import(R.viewer);

// The worker has to come from a blob: webview resources live on another
// origin, and a Worker can only be started from its own.
const workerSource = await (await fetch(R.worker)).text();
const worker = new pdfjsLib.PDFWorker({
    port: new Worker(URL.createObjectURL(new Blob([workerSource], { type: 'text/javascript' })), { type: 'module' }),
});

// ── zathurarc ───────────────────────────────────────────────────────────
// zathura's own defaults, overridden by whatever zathurarc sets.
const DEFAULTS = {
    'default-bg': '#000000', 'default-fg': '#DDDDDD',
    'statusbar-bg': '#000000', 'statusbar-fg': '#FFFFFF',
    'inputbar-bg': '#131313', 'inputbar-fg': '#9FBC00',
    'notification-bg': '#FFFFFF', 'notification-fg': '#000000',
    'notification-error-bg': '#FFFFFF', 'notification-error-fg': '#FF1212',
    'notification-warning-bg': '#FFFFFF', 'notification-warning-fg': '#FFE700',
    'index-bg': '#232323', 'index-fg': '#DDDDDD',
    'index-active-bg': '#9FBC00', 'index-active-fg': '#232323',
    // current zathura carries the alpha in the colour itself (rgba());
    // highlight-transparency only applies if an older zathurarc still sets it
    'highlight-color': 'rgba(159,251,0,0.5)', 'highlight-active-color': 'rgba(0,188,0,0.5)',
    'highlight-fg': 'rgba(0,0,0,0.5)', 'highlight-transparency': '1',
    'render-loading': 'true', 'render-loading-bg': '#FFFFFF', 'render-loading-fg': '#000000',
    'recolor': 'false', 'recolor-keephue': 'false',
    'recolor-lightcolor': '#000000', 'recolor-darkcolor': '#FFFFFF',
    'font': 'monospace normal 9',
    'guioptions': 's',
    'statusbar-h-padding': '8', 'statusbar-v-padding': '2',
    'statusbar-page-percent': 'false',
    'page-padding': '1', 'page-v-padding': '', 'page-h-padding': '',
    'adjust-open': 'best-fit',
    'pages-per-row': '1', 'first-page-column': '1:2',
    'scroll-step': '40', 'scroll-hstep': '-1', 'scroll-full-overlap': '0',
    'scroll-page-aware': 'false',
    'zoom-step': '10', 'zoom-min': '10', 'zoom-max': '1000',
    'incremental-search': 'true',
    'selection-clipboard': 'primary',
};

// zathura's default normal- and index-mode bindings, in zathurarc syntax so
// they go through the same parser as the user's maps.
const DEFAULT_MAPS = `
J navigate next
K navigate previous
<PageDown> navigate next
<PageUp> navigate previous
<A-Right> navigate next
<A-Left> navigate previous
h scroll left
j scroll down
k scroll up
l scroll right
<Left> scroll left
<Down> scroll down
<Up> scroll up
<Right> scroll right
<C-t> scroll half-left
<C-d> scroll half-down
<C-u> scroll half-up
<C-y> scroll half-right
t scroll full-left
<C-f> scroll full-down
<C-b> scroll full-up
<Space> scroll full-down
<S-Space> scroll full-up
<BackSpace> scroll full-up
y scroll full-right
gg goto top
G goto bottom
<Home> goto top
<End> goto bottom
P snap_to_page
<C-o> jumplist backward
<C-i> jumplist forward
<Esc> abort
<C-[> abort
a adjust_window best-fit
s adjust_window width
/ focus_inputbar /
? focus_inputbar ?
n search forward
N search backward
f follow
F display_link
c copy_link
r rotate rotate-cw
<C-r> recolor
R reload
<Tab> toggle_index
d toggle_page_mode
<C-n> toggle_statusbar
+ zoom in
- zoom out
= zoom specific
zI zoom in
zO zoom out
z0 zoom specific
m mark_add
' mark_evaluate
q quit
[index] k navigate_index up
[index] j navigate_index down
[index] <Up> navigate_index up
[index] <Down> navigate_index down
[index] h navigate_index collapse
[index] l navigate_index expand
[index] <Left> navigate_index collapse
[index] <Right> navigate_index expand
[index] H navigate_index collapse-all
[index] L navigate_index expand-all
[index] gg navigate_index top
[index] G navigate_index bottom
[index] <Space> navigate_index select
[index] <Return> navigate_index select
[index] <Tab> toggle_index
[index] <Esc> toggle_index
[index] <C-[> toggle_index
[index] q quit
`.trim().split('\n').map(line => {
    const w = line.split(/\s+/);
    const mode = w[0].startsWith('[') ? w.shift().slice(1, -1) : 'normal';
    return { mode, keys: w[0], fn: w[1], arg: w[2] ?? null };
});

let opt = { ...DEFAULTS };
let rcRecolor = null;
const bool = k => opt[k] === 'true';
const num = (k, fallback = 0) => {
    const v = parseFloat(opt[k]);
    return Number.isFinite(v) ? v : fallback;
};

// Key names: zathura/girara spellings on the config side, KeyboardEvent.key
// on the event side, both normalised to e.g. "j", "<C-d>", "<S-Space>".
const KEY_NAMES = {
    space: 'Space', esc: 'Esc', escape: 'Esc', return: 'Return', enter: 'Return', cr: 'Return',
    backspace: 'BackSpace', bs: 'BackSpace', tab: 'Tab', up: 'Up', down: 'Down', left: 'Left',
    right: 'Right', pageup: 'PageUp', page_up: 'PageUp', pagedown: 'PageDown', page_down: 'PageDown',
    home: 'Home', end: 'End', delete: 'Delete', del: 'Delete', insert: 'Insert', minus: '-',
    plus: '+', equal: '=', less: '<', greater: '>',
};
const EVENT_NAMES = {
    ' ': 'Space', Escape: 'Esc', Enter: 'Return', Backspace: 'BackSpace', Tab: 'Tab',
    ArrowUp: 'Up', ArrowDown: 'Down', ArrowLeft: 'Left', ArrowRight: 'Right',
    PageUp: 'PageUp', PageDown: 'PageDown', Home: 'Home', End: 'End', Delete: 'Delete', Insert: 'Insert',
};

function token(mods, name) {
    // Shift is part of a printable character ("G", "?"), not a modifier.
    const m = ['C', 'A', 'S'].filter(x => mods.has(x) && !(x === 'S' && name.length === 1));
    if (!m.length && name.length === 1) return name;
    return `<${[...m, name].join('-')}>`;
}

function parseKeys(s) {
    const out = [];
    for (let i = 0; i < s.length;) {
        const close = s[i] === '<' ? s.indexOf('>', i + 2) : -1;
        if (close > 0) {
            const parts = s.slice(i + 1, close).split('-');
            let name = parts.pop() || '-';
            const mods = new Set(parts.map(p => p.toUpperCase()));
            if (name.length > 1) {
                const f = /^f(\d+)$/i.exec(name);
                name = f ? `F${f[1]}` : KEY_NAMES[name.toLowerCase()];
                if (!name) return null; // mouse buttons and other things we can't bind
            }
            out.push(token(mods, name));
            i = close + 1;
        } else {
            out.push(s[i++]);
        }
    }
    return out.length ? out : null;
}

function eventToken(e) {
    let name = EVENT_NAMES[e.key] ?? (/^F\d+$/.test(e.key) || e.key.length === 1 ? e.key : null);
    if (!name) return null;
    const mods = new Set();
    if (e.ctrlKey) mods.add('C');
    if (e.altKey) mods.add('A');
    if (e.shiftKey) mods.add('S');
    return token(mods, name);
}

const FUNCTIONS = {}; // filled in below; keymap entries point at these by name
let keymap = { normal: [], index: [] };

function buildKeymap(userMaps) {
    keymap = { normal: [], index: [] };
    for (const m of [...DEFAULT_MAPS, ...userMaps]) {
        const list = keymap[m.mode];
        if (!list) continue; // [fullscreen], [presentation]: no such modes here
        const seq = parseKeys(m.keys);
        if (!seq) continue;
        const key = seq.join(' ');
        const i = list.findIndex(b => b.key === key);
        if (i >= 0) list.splice(i, 1);
        if (m.fn && FUNCTIONS[m.fn]) list.push({ key, seq, fn: m.fn, arg: m.arg });
    }
}

const colorCtx = document.createElement('canvas').getContext('2d');
function rgb(color) {
    colorCtx.fillStyle = '#000';
    colorCtx.fillStyle = color;
    const v = colorCtx.fillStyle;
    if (v[0] === '#') return [1, 3, 5].map(i => parseInt(v.slice(i, i + 2), 16) / 255);
    return v.match(/[\d.]+/g).slice(0, 3).map(x => x / 255);
}
const withAlpha = (color, a) => `color-mix(in srgb, ${color} ${Math.round(a * 100)}%, transparent)`;

// zathura's recolour as one GPU colour matrix on the page canvases. Plain:
// each pixel's luminance l maps linearly from darkcolor (l=0) to lightcolor
// (l=1). keephue: the same lightness shift, but each channel keeps its
// offset from the grey, so links and figures stay coloured.
function updateRecolorMatrix() {
    const L = rgb(opt['recolor-lightcolor']);
    const D = rgb(opt['recolor-darkcolor']);
    const w = [0.2126, 0.7152, 0.0722];
    const keep = bool('recolor-keephue');
    const rows = [0, 1, 2].map(c => {
        const s = L[c] - D[c];
        const coef = w.map((wk, k) => (keep ? (k === c ? 1 : 0) + (s - 1) * wk : s * wk));
        return [...coef, 0, D[c]].map(x => x.toFixed(4)).join(' ');
    });
    rows.push('0 0 0 1 0');
    $('recolor-matrix').setAttribute('values', rows.join('  '));
}

let recolorOn = false;
function setRecolor(on) {
    recolorOn = on;
    body.classList.toggle('recolor', on);
    root.setProperty('--page-bg', on ? opt['recolor-lightcolor'] : '#ffffff');
    saveState();
}

// Pango font description ("JetBrainsMono Nerd Font Bold 11") to CSS.
function applyFont(desc) {
    const words = desc.split(/\s+/).filter(Boolean);
    let size = '9pt';
    const last = words[words.length - 1];
    if (/^\d+(\.\d+)?(px)?$/.test(last ?? '')) {
        words.pop();
        size = last.endsWith('px') ? last : `${last}pt`;
    }
    let weight = 'normal';
    let style = 'normal';
    const STYLE = /^(normal|regular|bold|italic|oblique|light|medium|semibold|heavy|book|ultra-light|ultra-bold|condensed|semi-condensed)$/i;
    while (words.length > 1 && STYLE.test(words[words.length - 1])) {
        const s = words.pop().toLowerCase();
        if (s === 'bold' || s === 'ultra-bold' || s === 'heavy') weight = 'bold';
        if (s === 'semibold') weight = '600';
        if (s === 'medium') weight = '500';
        if (s === 'light' || s === 'ultra-light') weight = '300';
        if (s === 'italic' || s === 'oblique') style = s;
    }
    const families = words.join(' ').split(',').map(f => f.trim()).filter(Boolean);
    root.setProperty('--font', [...families.map(f => (f === 'monospace' ? f : `"${f}"`)), 'monospace'].join(', '));
    root.setProperty('--font-size', size);
    body.style.fontWeight = weight;
    body.style.fontStyle = style;
}

function updateStatusbarHeight() {
    root.setProperty('--statusbar-height', body.classList.contains('no-statusbar') ? '0px' : `${statusbar.offsetHeight}px`);
}

let configured = false;
function applyConfig(rc, title) {
    opt = { ...DEFAULTS, ...rc.options };
    const colors = [
        'default-bg', 'default-fg', 'statusbar-bg', 'statusbar-fg', 'inputbar-bg', 'inputbar-fg',
        'notification-bg', 'notification-fg', 'notification-error-bg', 'notification-error-fg',
        'notification-warning-bg', 'notification-warning-fg', 'index-bg', 'index-fg',
        'index-active-bg', 'index-active-fg', 'highlight-fg', 'render-loading-bg', 'render-loading-fg',
    ];
    for (const k of colors) root.setProperty(`--${k}`, opt[k]);
    const alpha = Math.min(1, Math.max(0, num('highlight-transparency', 0.5)));
    root.setProperty('--highlight-color', withAlpha(opt['highlight-color'], alpha));
    root.setProperty('--highlight-active-color', withAlpha(opt['highlight-active-color'], alpha));
    root.setProperty('--highlight-solid', opt['highlight-color']);
    // page-padding was split into page-v-padding / page-h-padding
    root.setProperty('--page-padding', `${num('page-v-padding', num('page-padding', 1))}px`);
    root.setProperty('--sb-hpad', `${num('statusbar-h-padding', 8)}px`);
    root.setProperty('--sb-vpad', `${num('statusbar-v-padding', 2)}px`);
    applyFont(opt.font);

    const gui = opt.guioptions;
    body.classList.toggle('no-vscroll', !gui.includes('v'));
    body.classList.toggle('no-hscroll', !gui.includes('h'));
    body.classList.toggle('no-render-loading', !bool('render-loading'));
    // Statusbar and recolour can be toggled at runtime; a config reload only
    // resets them when the config itself changed that setting.
    if (!configured) body.classList.toggle('no-statusbar', !gui.includes('s'));
    updateRecolorMatrix();
    if (!configured || opt.recolor !== rcRecolor) {
        setRecolor(!configured && savedState.recolor !== undefined ? savedState.recolor : bool('recolor'));
    } else {
        setRecolor(recolorOn);
    }
    rcRecolor = opt.recolor;

    buildKeymap(rc.maps);
    $('sb-left').textContent = title;
    updateStatusbarHeight();
    configured = true;
}

// ── pdf.js viewer ───────────────────────────────────────────────────────
const { SpreadMode } = pdfjsViewer;
const eventBus = new pdfjsViewer.EventBus();
const linkService = new pdfjsViewer.PDFLinkService({ eventBus });
const findController = new pdfjsViewer.PDFFindController({ eventBus, linkService });
const viewer = new pdfjsViewer.PDFViewer({
    container,
    viewer: viewerEl,
    eventBus,
    linkService,
    findController,
    removePageBorders: true,
    // Links, but no fillable forms: form fields would fight the keymap.
    annotationMode: pdfjsLib.AnnotationMode.ENABLE,
    // Plain CSS ::selection, so selections show in highlight-color and are
    // not painted onto the canvas (where recolour would tint them).
    enableSelectionRendering: false,
    // pdf.js caps canvases at a multiple of window.screen's area. A webview
    // has no say in what that reports (0x0 off-screen), and a zero cap
    // leaves pages blank apart from partial "detail" tiles. -1 keeps only
    // pdf.js's own pixel limit.
    capCanvasAreaFactor: -1,
    imageResourcesPath: R.images,
});
linkService.setViewer(viewer);

let pdfDoc = null;
let shownTask = null;
let pendingTask = null;
let pendingRestore = null;
const savedState = vscode.getState() ?? {};
const marks = savedState.marks ?? {};

function pageRect(n) {
    const div = viewer.getPageView(n - 1)?.div;
    if (!div) return null;
    const r = div.getBoundingClientRect();
    const c = container.getBoundingClientRect();
    return { top: r.top - c.top + container.scrollTop, height: r.height };
}

// Positions are page-relative, so they survive zoom, rotation and reloads.
function position() {
    const n = viewer.pagesCount;
    if (!n) return null;
    const y = container.scrollTop + 1;
    let lo = 1;
    let hi = n;
    while (lo < hi) {
        const mid = (lo + hi + 1) >> 1;
        if (pageRect(mid).top <= y) lo = mid;
        else hi = mid - 1;
    }
    const r = pageRect(lo);
    return {
        page: lo,
        frac: (container.scrollTop - r.top) / Math.max(1, r.height),
        left: container.scrollLeft / Math.max(1, container.scrollWidth),
    };
}

function restore(p) {
    if (!p || p.page > viewer.pagesCount) return;
    const r = pageRect(p.page);
    container.scrollTop = r.top + p.frac * r.height;
    container.scrollLeft = p.left * container.scrollWidth;
}

let saveTimer = null;
function saveState() {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(() => {
        if (!viewer.pagesCount) return;
        vscode.setState({
            pos: position(),
            scale: viewer.currentScaleValue,
            rotation: viewer.pagesRotation,
            spread: viewer.spreadMode,
            recolor: recolorOn,
            marks,
        });
    }, 300);
}

function adjustOpen() {
    return opt['adjust-open'] === 'width' ? 'page-width' : 'page-fit';
}

function dualSpread() {
    // first-page-column "a:b:c": the column page 1 sits in, for 1, 2, 3...
    // pages per row. Column 2 at two per row is a book layout (EVEN).
    const cols = opt['first-page-column'].split(':');
    return (cols[1] ?? '1') === '1' ? SpreadMode.ODD : SpreadMode.EVEN;
}

eventBus.on('pagesinit', () => {
    const s = pendingRestore;
    pendingRestore = null;
    viewer.pagesRotation = s?.rotation ?? 0;
    viewer.spreadMode = s?.spread ?? (num('pages-per-row', 1) >= 2 ? dualSpread() : SpreadMode.NONE);
    viewer.currentScaleValue = s?.scale ?? adjustOpen();
    if (s?.pos) restore(s.pos);
    updateStatus();
});
eventBus.on('pagechanging', updateStatus);

// pdf.js leaves fit modes alone on resize; zathura re-fits.
new ResizeObserver(() => {
    const v = viewer.currentScaleValue;
    if (v === 'page-fit' || v === 'page-width') viewer.currentScaleValue = v;
}).observe(container);

async function openDocument(url, reload) {
    let data;
    try {
        const res = await fetch(url);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        data = new Uint8Array(await res.arrayBuffer());
    } catch (err) {
        // On reload the file may be mid-rewrite (latexmk and friends replace
        // it); the watcher fires again once the new one lands.
        if (!reload) notify(`Could not read document: ${err.message}`, 'error');
        return;
    }
    if (reload && !data.length) return;
    const restoreTo = reload && viewer.pagesCount
        ? { pos: position(), scale: viewer.currentScaleValue, rotation: viewer.pagesRotation, spread: viewer.spreadMode }
        : (reload ? pendingRestore : savedState);
    const task = pdfjsLib.getDocument({
        data,
        worker,
        cMapUrl: R.cmaps,
        cMapPacked: true,
        standardFontDataUrl: R.fonts,
        wasmUrl: R.wasm,
        iccUrl: R.iccs,
        // Fetch fonts/cmaps on this thread: the blob worker can't reach
        // webview resources.
        useWorkerFetch: false,
        isEvalSupported: false,
    });
    task.onPassword = (update, reason) => {
        const again = reason === pdfjsLib.PasswordResponses.INCORRECT_PASSWORD;
        openInput({
            prompt: again ? 'Incorrect password, try again: ' : 'Enter password: ',
            password: true,
            submit: update,
            cancel: () => task.destroy(),
        });
    };
    // A newer load supersedes one still in flight; the document on screen
    // stays up until its replacement has loaded.
    pendingTask?.destroy();
    pendingTask = task;
    let doc;
    try {
        doc = await task.promise;
    } catch (err) {
        if (task !== pendingTask) return;
        pendingTask = null;
        if (err?.name !== 'AbortException') notify(`${reload ? 'Reload failed' : 'Could not open document'}: ${err?.message ?? err}`, 'error');
        return;
    }
    if (task !== pendingTask) return;
    pendingTask = null;
    const oldTask = shownTask;
    shownTask = task;
    pdfDoc = doc;
    outline = null;
    closeIndex();
    endHints();
    pendingRestore = restoreTo;
    viewer.setDocument(doc);
    linkService.setDocument(doc);
    oldTask?.destroy();
    container.focus();
}

// ── statusbar, inputbar, notifications ──────────────────────────────────
function updateStatus() {
    const n = viewer.pagesCount;
    let text = n ? `[${viewer.currentPageNumber}/${n}]` : '';
    if (n && bool('statusbar-page-percent')) {
        const max = container.scrollHeight - container.clientHeight;
        text += ` (${max > 0 ? Math.round((container.scrollTop / max) * 100) : 0}%)`;
    }
    $('sb-page').textContent = text;
}

function showPending() {
    $('sb-keys').textContent = count + pending.join('');
}

let notifying = false;
function notify(text, level = '') {
    if (inputMode) return;
    inputbar.className = `notify ${level}`;
    promptEl.textContent = text;
    notifying = true;
}
function clearNotify() {
    if (!notifying) return;
    notifying = false;
    inputbar.className = '';
    promptEl.textContent = '';
}

let inputMode = null;
function openInput(mode) {
    clearNotify();
    inputMode = mode;
    promptEl.textContent = mode.prompt;
    input.type = mode.password ? 'password' : 'text';
    input.value = '';
    inputbar.className = 'active';
    input.focus();
}
function closeInput() {
    inputMode = null;
    inputbar.className = '';
    input.value = '';
    input.blur();
    container.focus();
}

input.addEventListener('input', () => inputMode?.change?.(input.value));

function inputKey(e) {
    if (e.key === 'Escape' || (e.ctrlKey && e.key === '[') || (e.key === 'Backspace' && !input.value)) {
        const m = inputMode;
        closeInput();
        m.cancel?.();
        return 'consume';
    }
    if (e.key === 'Enter') {
        const m = inputMode;
        const value = input.value;
        closeInput();
        m.submit?.(value);
        return 'consume';
    }
    // Clipboard and select-all go through VS Code, which pipes them back in.
    if ((e.ctrlKey || e.metaKey) && /^[acvxyz]$/i.test(e.key)) return 'pass';
    return 'isolate';
}

// ── search ──────────────────────────────────────────────────────────────
let lastSearch = null; // { query, backward }
let dispatchedQuery = null;

function find(query, type, backward) {
    dispatchedQuery = query;
    eventBus.dispatch('find', {
        source: null,
        type,
        query,
        // smart case: an uppercase letter makes the search case-sensitive
        caseSensitive: query !== query.toLowerCase(),
        entireWord: false,
        highlightAll: true,
        findPrevious: backward,
        matchDiacritics: false,
    });
}

function clearSearch() {
    dispatchedQuery = null;
    eventBus.dispatch('findbarclose', { source: null });
}

eventBus.on('updatefindcontrolstate', ({ state, rawQuery }) => {
    if (state === pdfjsViewer.FindState.NOT_FOUND && rawQuery) notify(`Pattern not found: ${rawQuery}`, 'error');
});

function startSearch(backward) {
    const from = position();
    openInput({
        prompt: backward ? '?' : '/',
        change: q => {
            if (!bool('incremental-search')) return;
            if (q) find(q, '', backward);
            else { clearSearch(); restore(from); }
        },
        submit: q => {
            if (!q) return;
            pushJump(from);
            lastSearch = { query: q, backward };
            if (q !== dispatchedQuery) find(q, '', backward);
        },
        cancel: () => {
            clearSearch();
            restore(from);
        },
    });
}

// ── jumplist and marks ──────────────────────────────────────────────────
const jumps = [];
let jumpIndex = 0;
function pushJump(p = position()) {
    if (!p) return;
    jumps.length = jumpIndex;
    jumps.push(p);
    if (jumps.length > 100) jumps.shift();
    jumpIndex = jumps.length;
}

// ── link hints (f, F, c) ────────────────────────────────────────────────
let hints = null; // { action, typed, links: [{ a, label }] }

function visibleLinks() {
    const c = container.getBoundingClientRect();
    const bottom = c.bottom;
    const links = [];
    for (const a of viewerEl.querySelectorAll('.annotationLayer .linkAnnotation > a')) {
        const r = a.getBoundingClientRect();
        if (!r.width || r.bottom < c.top || r.top > bottom || r.right < c.left || r.left > c.right) continue;
        links.push({ a, r });
    }
    links.sort((x, y) => x.r.top - y.r.top || x.r.left - y.r.left);
    return links;
}

function startHints(action) {
    const links = visibleLinks();
    if (!links.length) {
        notify('No links on the visible pages', 'warning');
        return;
    }
    hintsEl.replaceChildren();
    const c = container.getBoundingClientRect();
    hints = { action, typed: '', links: links.map(({ a, r }, i) => ({ a, label: String(i + 1) })) };
    links.forEach(({ r }, i) => {
        const box = document.createElement('div');
        box.className = 'box';
        Object.assign(box.style, { left: `${r.left - c.left}px`, top: `${r.top - c.top}px`, width: `${r.width}px`, height: `${r.height}px` });
        const label = document.createElement('div');
        label.className = 'label';
        label.textContent = String(i + 1);
        Object.assign(label.style, { left: `${r.left - c.left}px`, top: `${r.top - c.top}px` });
        hintsEl.append(box, label);
    });
    hintsEl.className = 'active';
    showHintPrompt();
}

function showHintPrompt() {
    const word = { follow: 'Follow', display: 'Display', copy: 'Copy' }[hints.action];
    inputbar.className = 'active';
    promptEl.textContent = `${word} hint: ${hints.typed}`;
}

function endHints() {
    if (!hints) return;
    hints = null;
    hintsEl.className = '';
    hintsEl.replaceChildren();
    inputbar.className = '';
    promptEl.textContent = '';
}

// Page number of a PDF destination: a named one, an explicit [ref, ...]
// array, or pdf.js's "page=N".
async function destPage(dest) {
    try {
        if (typeof dest === 'string') {
            const m = /^page=(\d+)/.exec(dest);
            if (m) return Number(m[1]);
            dest = await pdfDoc.getDestination(dest);
        }
        if (!Array.isArray(dest)) return null;
        const ref = dest[0];
        return (Number.isInteger(ref) ? ref : await pdfDoc.getPageIndex(ref)) + 1;
    } catch {
        return null;
    }
}

// Internal links carry the destination in the hash (JSON for explicit ones).
async function linkTarget(a) {
    const href = a.getAttribute('href') ?? '';
    if (!href.startsWith('#')) return a.href || href;
    const hash = decodeURIComponent(href.slice(1));
    let dest = hash;
    try { dest = JSON.parse(hash); } catch {}
    const page = await destPage(dest);
    return page ? `page ${page}` : hash;
}

async function actOnLink(a, action) {
    const target = action === 'follow' ? null : await linkTarget(a);
    if (action === 'display') {
        notify(`Link: ${target}`);
    } else if (action === 'copy') {
        vscode.postMessage({ type: 'copy', text: target });
        notify(`Copied to clipboard: ${target}`);
    } else if ((a.getAttribute('href') ?? '').startsWith('#') || !a.href) {
        pushJump();
        a.click();
    } else {
        vscode.postMessage({ type: 'openExternal', url: a.href });
    }
}

function hintKey(e) {
    if (e.key === 'Escape' || (e.ctrlKey && e.key === '[')) {
        endHints();
        return 'consume';
    }
    if (e.key === 'Backspace') {
        hints.typed = hints.typed.slice(0, -1);
    } else if (/^\d$/.test(e.key)) {
        hints.typed += e.key;
    } else if (e.key !== 'Enter') {
        return 'consume';
    }
    const typed = hints.typed;
    const exact = hints.links.find(l => l.label === typed);
    const longer = hints.links.some(l => l.label !== typed && l.label.startsWith(typed));
    if (exact && (e.key === 'Enter' || !longer)) {
        const action = hints.action;
        endHints();
        actOnLink(exact.a, action);
    } else if (e.key === 'Enter') {
        endHints();
    } else {
        showHintPrompt();
    }
    return 'consume';
}

// ── index (Tab) ─────────────────────────────────────────────────────────
let outline = null; // tree of { title, dest, url, children, parent, depth, page, open }
let indexOpen = false;
let indexActive = null;

async function loadOutline() {
    const raw = await pdfDoc.getOutline();
    if (!raw?.length) return [];
    const build = (items, parent, depth) => items.map(it => {
        const node = { title: it.title, dest: it.dest, url: it.url, parent, depth, page: null, open: false };
        node.children = build(it.items ?? [], node, depth + 1);
        return node;
    });
    const tree = build(raw, null, 0);
    const all = flatten(tree, true);
    await Promise.all(all.map(async node => {
        if (node.dest) node.page = await destPage(node.dest);
    }));
    return tree;
}

function flatten(nodes, all = false, out = []) {
    for (const n of nodes) {
        out.push(n);
        if (all || n.open) flatten(n.children, all, out);
    }
    return out;
}

async function openIndex() {
    if (!pdfDoc) return;
    const doc = pdfDoc;
    if (!outline) {
        const tree = await loadOutline();
        if (doc !== pdfDoc) return;
        outline = tree;
    }
    if (!outline.length) {
        notify('This document does not contain any index', 'error');
        return;
    }
    // Start on the entry for the current page, its parents unfolded.
    const page = viewer.currentPageNumber;
    let best = outline[0];
    for (const n of flatten(outline, true)) if (n.page !== null && n.page <= page) best = n;
    for (let p = best.parent; p; p = p.parent) p.open = true;
    indexActive = best;
    indexOpen = true;
    indexEl.className = 'active';
    renderIndex();
}

function closeIndex() {
    indexOpen = false;
    indexEl.className = '';
    container.focus();
}

function renderIndex() {
    const rows = flatten(outline);
    indexEl.replaceChildren(...rows.map(n => {
        const row = document.createElement('div');
        row.className = n === indexActive ? 'entry active' : 'entry';
        const title = document.createElement('span');
        title.className = 'title';
        const marker = n.children.length ? (n.open ? '▾ ' : '▸ ') : '  ';
        title.textContent = '  '.repeat(n.depth) + marker + n.title;
        const page = document.createElement('span');
        page.textContent = n.page ?? '';
        row.append(title, page);
        row.addEventListener('click', () => {
            indexActive = n;
            selectIndex();
        });
        return row;
    }));
    indexEl.querySelector('.active')?.scrollIntoView({ block: 'nearest' });
}

function selectIndex() {
    const n = indexActive;
    closeIndex();
    if (n.url) {
        vscode.postMessage({ type: 'openExternal', url: n.url });
    } else if (n.dest) {
        pushJump();
        linkService.goToDestination(n.dest);
    }
}

// ── the zathura functions keys are mapped to ────────────────────────────
let count = '';
let pending = [];
let pendingTimer = null;
let awaitingMark = null;

const clampScale = s => Math.min(num('zoom-max', 1000) / 100, Math.max(num('zoom-min', 10) / 100, s));

function scrollBy(dy, dx) {
    container.scrollBy({ top: dy, left: dx, behavior: 'instant' });
}

Object.assign(FUNCTIONS, {
    abort() {
        clearSearch();
        endHints();
        clearNotify();
    },

    adjust_window(arg) {
        viewer.currentScaleValue = arg === 'width' ? 'page-width' : 'page-fit';
    },

    navigate(arg, n) {
        for (let i = 0; i < (n ?? 1); i++) {
            if (arg === 'previous') viewer.previousPage();
            else viewer.nextPage();
        }
    },

    scroll(arg, n) {
        n ??= 1;
        const step = num('scroll-step', 40);
        const hstep = num('scroll-hstep', -1) < 0 ? step : num('scroll-hstep');
        const H = container.clientHeight;
        const W = container.clientWidth;
        const full = 1 - Math.min(1, Math.max(0, num('scroll-full-overlap')));
        const moves = {
            up: [-step, 0], down: [step, 0], left: [0, -hstep], right: [0, hstep],
            'half-up': [-H / 2, 0], 'half-down': [H / 2, 0], 'half-left': [0, -W / 2], 'half-right': [0, W / 2],
            'full-up': [-H * full, 0], 'full-down': [H * full, 0], 'full-left': [0, -W * full], 'full-right': [0, W * full],
        };
        let [dy, dx] = moves[arg] ?? [0, 0];
        dy *= n;
        dx *= n;
        // scroll-page-aware: a full-page scroll stops at the next page edge.
        if (arg?.startsWith('full-') && dy && bool('scroll-page-aware')) {
            const top = container.scrollTop;
            for (let p = 1; p <= viewer.pagesCount; p++) {
                const t = pageRect(p).top;
                if (dy > 0 && t > top + 1 && t < top + dy) { dy = t - top; break; }
                if (dy < 0 && t < top - 1 && t > top + dy) dy = t - top;
            }
        }
        scrollBy(dy, dx);
    },

    goto(arg, n) {
        pushJump();
        if (n) viewer.scrollPageIntoView({ pageNumber: Math.min(Math.max(1, n), viewer.pagesCount) });
        else container.scrollTop = arg === 'bottom' ? container.scrollHeight : 0;
    },

    snap_to_page() {
        viewer.scrollPageIntoView({ pageNumber: viewer.currentPageNumber });
    },

    jumplist(arg, n) {
        n ??= 1;
        if (arg === 'backward') {
            if (jumpIndex === jumps.length) jumps.push(position());
            const to = Math.max(0, jumpIndex - n);
            if (to === jumpIndex) return;
            jumpIndex = to;
        } else {
            const to = Math.min(jumps.length - 1, jumpIndex + n);
            if (to <= jumpIndex) return;
            jumpIndex = to;
        }
        restore(jumps[jumpIndex]);
    },

    focus_inputbar(arg) {
        if (arg === '/' || arg === '?') startSearch(arg === '?');
    },

    search(arg, n) {
        if (!lastSearch) return;
        const backward = (arg === 'backward') !== lastSearch.backward;
        if (dispatchedQuery !== lastSearch.query) {
            find(lastSearch.query, '', backward);
            return;
        }
        for (let i = 0; i < (n ?? 1); i++) find(lastSearch.query, 'again', backward);
    },

    follow() { startHints('follow'); },
    display_link() { startHints('display'); },
    copy_link() { startHints('copy'); },

    rotate(arg, n) {
        const deg = (arg === 'rotate-ccw' ? -90 : 90) * (n ?? 1);
        viewer.pagesRotation = (((viewer.pagesRotation + deg) % 360) + 360) % 360;
        saveState();
    },

    recolor() { setRecolor(!recolorOn); },

    reload() { vscode.postMessage({ type: 'reload' }); },

    toggle_index() {
        if (indexOpen) closeIndex();
        else openIndex();
    },

    toggle_page_mode() {
        viewer.spreadMode = viewer.spreadMode === SpreadMode.NONE ? dualSpread() : SpreadMode.NONE;
        saveState();
    },

    toggle_statusbar() {
        body.classList.toggle('no-statusbar');
        updateStatusbarHeight();
    },

    zoom(arg, n) {
        const step = num('zoom-step', 10) / 100;
        let s = viewer.currentScale;
        if (arg === 'in') s += step * (n ?? 1);
        else if (arg === 'out') s -= step * (n ?? 1);
        else s = (n ?? 100) / 100;
        viewer.currentScale = clampScale(s);
        saveState();
    },

    mark_add() { awaitingMark = 'add'; },
    mark_evaluate() { awaitingMark = 'evaluate'; },

    quit() { vscode.postMessage({ type: 'quit' }); },

    navigate_index(arg, n) {
        n ??= 1;
        const rows = flatten(outline);
        let i = rows.indexOf(indexActive);
        const node = indexActive;
        switch (arg) {
            case 'up': i = Math.max(0, i - n); break;
            case 'down': i = Math.min(rows.length - 1, i + n); break;
            case 'top': i = 0; break;
            case 'bottom': i = rows.length - 1; break;
            case 'expand':
                if (node.children.length) node.open = true;
                break;
            case 'collapse':
                if (node.open && node.children.length) node.open = false;
                else if (node.parent) { node.parent.open = false; indexActive = node.parent; }
                break;
            case 'expand-all':
                flatten(outline, true).forEach(x => { x.open = true; });
                break;
            case 'collapse-all':
                flatten(outline, true).forEach(x => { x.open = false; });
                while (indexActive.parent) indexActive = indexActive.parent;
                break;
            case 'select':
                selectIndex();
                return;
        }
        if (['up', 'down', 'top', 'bottom'].includes(arg)) indexActive = rows[i];
        renderIndex();
    },
});

function runBinding(b) {
    const n = count ? parseInt(count, 10) : null;
    count = '';
    pending = [];
    showPending();
    FUNCTIONS[b.fn](b.arg, n);
}

onKey = e => {
    if (e.isComposing || ['Shift', 'Control', 'Alt', 'Meta'].includes(e.key)) return 'pass';
    if (inputMode) return inputKey(e);
    if (hints) return hintKey(e);
    clearNotify();
    if (awaitingMark) {
        const kind = awaitingMark;
        awaitingMark = null;
        if (e.key.length === 1 && /\S/.test(e.key)) {
            if (kind === 'add') {
                marks[e.key] = position();
                saveState();
            } else if (marks[e.key]) {
                pushJump();
                restore(marks[e.key]);
            }
        }
        return 'consume';
    }
    const tok = eventToken(e);
    if (!tok) return 'pass';
    const mode = indexOpen ? 'index' : 'normal';
    if (!pending.length && /^[0-9]$/.test(tok) && (count || tok !== '0')) {
        count += tok;
        showPending();
        return 'consume';
    }
    clearTimeout(pendingTimer);
    pending.push(tok);
    const key = pending.join(' ');
    const candidates = keymap[mode].filter(b => b.key === key || b.key.startsWith(key + ' '));
    if (!candidates.length) {
        const wasPending = pending.length > 1 || count !== '';
        count = '';
        pending = [];
        showPending();
        return wasPending || indexOpen ? 'consume' : 'pass';
    }
    const exact = candidates.find(b => b.key === key);
    if (exact && candidates.length === 1) {
        runBinding(exact);
    } else {
        // A prefix of something longer: wait for the next key (and if this
        // is itself bound, run it after a pause, like girara does).
        showPending();
        if (exact) pendingTimer = setTimeout(() => runBinding(exact), 1000);
    }
    return 'consume';
};

// ── mouse ───────────────────────────────────────────────────────────────
// Ctrl+wheel zooms one zoom-step per notch. Touchpad pinches arrive as a
// stream of tiny Ctrl+wheel deltas, so add them up to notch-sized amounts.
let wheelZoom = 0;
container.addEventListener('wheel', e => {
    if (!e.ctrlKey) return;
    e.preventDefault();
    wheelZoom += e.deltaMode === 0 ? e.deltaY : e.deltaY * 40;
    while (Math.abs(wheelZoom) >= 50) {
        FUNCTIONS.zoom(wheelZoom < 0 ? 'in' : 'out', null);
        wheelZoom -= Math.sign(wheelZoom) * 50;
    }
}, { passive: false });

container.addEventListener('scroll', () => {
    if (hints) endHints();
    updateStatus();
    saveState();
});

// selection-clipboard clipboard: a finished selection lands on the
// clipboard, as zathura does.
container.addEventListener('mouseup', () => {
    if (opt['selection-clipboard'] !== 'clipboard') return;
    const text = window.getSelection()?.toString();
    if (text) vscode.postMessage({ type: 'copy', text });
});

// ── host messages ───────────────────────────────────────────────────────
window.addEventListener('message', e => {
    const msg = e.data;
    if (msg.type === 'config') applyConfig(msg.rc, msg.title);
    else if (msg.type === 'load') openDocument(msg.url, msg.reload);
    else if (msg.type === 'error') notify(msg.message, 'error');
});

$('sb-left').textContent = ' ';
vscode.postMessage({ type: 'ready' });
