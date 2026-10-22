// Stands in for VS Code's webview API, so media/viewer.js runs unchanged in
// a Firefox tab: acquireVsCodeApi() posts to here, and this answers with the
// same 'config' / 'load' / 'error' messages extension.js sends. Runs before
// viewer.js (a plain script ahead of its module).
'use strict';
(() => {
    const params = new URLSearchParams(location.search);
    const file = params.get('file');
    // Only ever navigated to or fetched: never a javascript: URL in here.
    if (!/^https?:\/\//i.test(file ?? '')) throw new Error(`pdf-zathura: not a web URL: ${file}`);
    const name = params.get('name') || baseName(file);
    // Sent as a download (or opened from dl-popup): Firefox would only
    // download it again, so a failed fetch is reported here instead.
    const attachment = params.has('attachment');
    const ext = p => browser.runtime.getURL(`media/pdfjs/${p}`);
    document.body.dataset.resources = JSON.stringify({
        pdf: ext('build/pdf.min.mjs'),
        worker: ext('build/pdf.worker.min.mjs'),
        viewer: ext('web/pdf_viewer.mjs'),
        images: ext('web/images/'),
        cmaps: ext('cmaps/'),
        fonts: ext('standard_fonts/'),
        wasm: ext('wasm/'),
        iccs: ext('iccs/'),
    });
    document.title = name;

    function baseName(url) {
        try {
            const u = new URL(url);
            return decodeURIComponent(u.pathname.split('/').pop()) || u.hostname;
        } catch {
            return url ?? 'PDF';
        }
    }

    function shown(url) {
        try { return decodeURI(url); } catch { return url; }
    }

    // viewer.js listens for 'message' events. Only the ones dispatched here
    // may reach it: a page holding a reference to this tab (window.opener)
    // could otherwise postMessage it a 'load'.
    window.addEventListener('message', e => {
        if (e.isTrusted) e.stopImmediatePropagation();
    }, true);
    const toViewer = data => window.dispatchEvent(new MessageEvent('message', { data }));

    // ── zathurarc, from background.js ───────────────────────────────────
    let rc = null;
    let ready = false;
    const port = browser.runtime.connect({ name: 'viewer' });
    port.onMessage.addListener(msg => {
        if (msg.type !== 'config') return;
        rc = msg.rc;
        if (ready) sendConfig();
    });
    const configured = new Promise(resolve => {
        const t = setInterval(() => rc && resolve(), 20);
        setTimeout(() => { clearInterval(t); resolve(); }, 1500);
    });

    function sendConfig() {
        const r = rc ?? { options: {}, maps: [] };
        const title = r.options['statusbar-basename'] === 'true' ? name : shown(file);
        toViewer({ type: 'config', rc: r, title });
    }

    // ── the document ────────────────────────────────────────────────────
    // Fetched again (the original load was redirected away), with the
    // site's cookies, and handed to viewer.js as a blob: URL.
    let blobUrl = null;

    // In a frame this page is third-party to the site, so its own requests
    // get the site's partitioned (usually empty) cookie jar; background.js
    // fetches with the real one.
    async function get(reload) {
        // The page load's own bytes, kept by background.js; fetching again
        // is the fallback (and what a reload does).
        if (!reload && params.has('cap')) {
            const data = await browser.runtime.sendMessage({ type: 'captured', id: params.get('id') });
            if (data) return { status: 200, type: 'application/pdf', data };
        }
        const init = { credentials: 'include', cache: reload ? 'no-cache' : 'default' };
        if (window.top !== window) return browser.runtime.sendMessage({ type: 'fetch', url: file, init });
        const res = await fetch(file, init);
        return { status: res.status, type: res.headers.get('content-type') ?? '', data: await res.blob() };
    }

    async function load(reload) {
        let blob;
        try {
            const { status, type, data } = await get(reload);
            if (status < 200 || status >= 300) throw new Error(`HTTP ${status}`);
            if (type && !/pdf|octet-stream|download|binary/i.test(type)) throw new Error(`got ${type.split(';')[0]}`);
            blob = new Blob([data], { type: 'application/pdf' });
            // Generic binaries are taken on their .pdf name; check it's one.
            if (!(await blob.slice(0, 1024).text()).includes('%PDF-')) throw new Error('not a PDF');
        } catch (err) {
            if (reload) toViewer({ type: 'error', message: `Reload failed: ${err.message}` });
            else if (attachment) toViewer({ type: 'error', message: `Can't preview this one (${err.message}). Ctrl+S hands it to dl-popup.` });
            // Expired link, a login page, a referrer check...: Firefox's own
            // viewer gets the original request instead.
            else toFirefox();
            return;
        }
        if (blobUrl) URL.revokeObjectURL(blobUrl);
        blobUrl = URL.createObjectURL(blob);
        toViewer({ type: 'load', url: blobUrl, reload });
    }

    async function toFirefox() {
        await browser.runtime.sendMessage({ type: 'firefox', url: file });
        location.replace(file);
    }

    // ── what viewer.js asks for ─────────────────────────────────────────
    async function tab() {
        return browser.tabs.getCurrent();
    }

    const handlers = {
        async ready() {
            // viewer.html is web-accessible, so any site could frame it with
            // a file of its choosing and have it fetched with that file's
            // cookies. Only viewers background.js sent a load to may fetch;
            // anything else (including a tab restored after a restart) loads
            // the file the ordinary way, which lands back here if it's a PDF.
            if (!await browser.runtime.sendMessage({ type: 'opened', id: params.get('id') })) {
                location.replace(file);
                return;
            }
            ready = true;
            await configured;
            sendConfig();
            load(false);
        },
        reload() {
            sendConfig();
            load(true);
        },
        async quit() {
            if (window.top === window) browser.tabs.remove((await tab()).id);
        },
        copy({ text }) {
            navigator.clipboard.writeText(text);
        },
        // zathura hands links to the browser; here that's a tab next to this one.
        async openExternal({ url }) {
            const t = await tab();
            browser.tabs.create({ url, index: t.index + 1, openerTabId: t.id });
        },
    };

    window.acquireVsCodeApi = () => ({
        postMessage: msg => handlers[msg.type]?.(msg),
        // Per history entry, so it survives F5 and back/forward like a webview's.
        getState: () => history.state?.viewer,
        setState: s => history.replaceState({ viewer: s }, ''),
    });

    // Saving goes through Firefox's downloads, i.e. to dl-popup.
    function save() {
        const as = /\.pdf$/i.test(name) ? name : `${name}.pdf`;
        browser.runtime.sendMessage({ type: 'save', url: file, name: as });
    }

    // Ctrl+S saves the PDF, not this page. Registered before viewer.js's
    // key listener, so this one sees the key first.
    window.addEventListener('keydown', e => {
        if (!e.ctrlKey || e.altKey || e.shiftKey || e.metaKey || e.key.toLowerCase() !== 's') return;
        e.preventDefault();
        e.stopImmediatePropagation();
        save();
    }, true);

    // The statusbar's save button. Never takes focus: Space/Enter would
    // press it instead of reaching viewer.js.
    const button = document.getElementById('save');
    button.addEventListener('mousedown', e => e.preventDefault());
    button.addEventListener('click', save);
})();
