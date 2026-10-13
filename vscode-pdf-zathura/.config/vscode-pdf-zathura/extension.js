// A zathura-flavoured PDF viewer inside VS Code: pdf.js does the rendering,
// media/viewer.js supplies zathura's keys, statusbar, index and recolour, and
// everything visual comes from the real ~/.config/zathura/zathurarc so the
// two stay in step with the desktop theme.
const vscode = require('vscode');
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { spawn } = require('child_process');
const { configDir, zathurarcPath, loadZathurarc } = require('./zathurarc');

const VIEW_TYPE = 'pdfZathura.view';

// Every open viewer, so a zathurarc change reaches all of them.
const panels = new Set();
let activeUri = null;

function displayPath(uri, opts) {
    if (uri.scheme !== 'file') return uri.toString();
    const p = uri.fsPath;
    const home = os.homedir();
    if (opts['statusbar-basename'] === 'true') return path.basename(p);
    if (opts['statusbar-home-tilde'] === 'true' && (p === home || p.startsWith(home + path.sep))) {
        return '~' + p.slice(home.length);
    }
    return p;
}

function html(webview, media) {
    const nonce = crypto.randomBytes(16).toString('base64');
    const u = (...p) => webview.asWebviewUri(vscode.Uri.joinPath(media, ...p)).toString();
    const resources = {
        pdf: u('pdfjs', 'build', 'pdf.min.mjs'),
        worker: u('pdfjs', 'build', 'pdf.worker.min.mjs'),
        viewer: u('pdfjs', 'web', 'pdf_viewer.mjs'),
        images: u('pdfjs', 'web', 'images') + '/',
        cmaps: u('pdfjs', 'cmaps') + '/',
        fonts: u('pdfjs', 'standard_fonts') + '/',
        wasm: u('pdfjs', 'wasm') + '/',
        iccs: u('pdfjs', 'iccs') + '/',
    };
    const src = webview.cspSource;
    const csp = [
        `default-src 'none'`,
        `img-src ${src} data: blob:`,
        `style-src ${src} 'unsafe-inline'`,
        `font-src ${src} data: blob:`,
        `script-src 'nonce-${nonce}' ${src} 'wasm-unsafe-eval'`,
        `worker-src blob:`,
        `connect-src ${src} data: blob:`,
    ].join('; ');
    const attr = s => s.replace(/&/g, '&amp;').replace(/'/g, '&#39;');
    return `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="${csp}">
<link rel="stylesheet" href="${u('pdfjs', 'web', 'pdf_viewer.css')}">
<link rel="stylesheet" href="${u('viewer.css')}">
</head>
<body data-resources='${attr(JSON.stringify(resources))}'>
<svg class="defs" aria-hidden="true">
  <filter id="recolor" color-interpolation-filters="sRGB">
    <feColorMatrix id="recolor-matrix" type="matrix" values="1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 1 0"/>
  </filter>
</svg>
<div id="viewerContainer" tabindex="-1"><div id="viewer" class="pdfViewer"></div></div>
<div id="hints"></div>
<div id="index"></div>
<div id="inputbar"><span id="prompt"></span><input id="input" spellcheck="false" autocomplete="off"></div>
<div id="statusbar"><span id="sb-left"></span><span id="sb-right"><span id="sb-keys"></span><span id="sb-page"></span></span></div>
<script type="module" nonce="${nonce}" src="${u('viewer.js')}"></script>
</body>
</html>`;
}

function openInZathura(uri) {
    if (!uri || uri.scheme !== 'file') {
        vscode.window.showErrorMessage('zathura can only open local files.');
        return;
    }
    const child = spawn('zathura', [uri.fsPath], { detached: true, stdio: 'ignore' });
    child.on('error', err => vscode.window.showErrorMessage(`zathura: ${err.message}`));
    child.unref();
}

class Provider {
    constructor(context) {
        this.media = vscode.Uri.joinPath(context.extensionUri, 'media');
    }

    openCustomDocument(uri) {
        return { uri, dispose() {} };
    }

    resolveCustomEditor(document, panel) {
        const uri = document.uri;
        const webview = panel.webview;
        const dir = vscode.Uri.joinPath(uri, '..');
        webview.options = { enableScripts: true, localResourceRoots: [this.media, dir] };
        webview.html = html(webview, this.media);

        const sendConfig = () => {
            const rc = loadZathurarc();
            webview.postMessage({ type: 'config', rc, title: displayPath(uri, rc.options) });
        };
        // The webview fetches the PDF itself. Bytes sent through postMessage
        // do not survive VS Code's message serialisation as a byte array, so
        // pdf.js rejects them. The query string defeats caching on reload.
        const sendDocument = reload => {
            const url = `${webview.asWebviewUri(uri).toString()}?v=${Date.now()}`;
            webview.postMessage({ type: 'load', url, reload });
        };

        // Auto-reload like zathura: re-read the PDF whenever it changes on disk.
        let timer = null;
        const changed = () => {
            clearTimeout(timer);
            timer = setTimeout(() => sendDocument(true), 300);
        };
        const watcher = vscode.workspace.createFileSystemWatcher(
            new vscode.RelativePattern(vscode.Uri.joinPath(uri, '..'), path.posix.basename(uri.path)));
        watcher.onDidChange(changed);
        watcher.onDidCreate(changed);

        const entry = { sendConfig };
        panels.add(entry);
        if (panel.active) activeUri = uri;
        panel.onDidChangeViewState(() => { if (panel.active) activeUri = uri; });

        webview.onDidReceiveMessage(msg => {
            switch (msg.type) {
                case 'ready':
                    sendConfig();
                    sendDocument(false);
                    break;
                case 'reload':
                    sendConfig();
                    sendDocument(true);
                    break;
                case 'quit':
                    panel.dispose();
                    break;
                case 'copy':
                    vscode.env.clipboard.writeText(msg.text);
                    break;
                case 'openExternal':
                    vscode.env.openExternal(vscode.Uri.parse(msg.url));
                    break;
            }
        });

        panel.onDidDispose(() => {
            clearTimeout(timer);
            watcher.dispose();
            panels.delete(entry);
            if (activeUri === uri) activeUri = null;
        });
    }
}

exports.activate = context => {
    context.subscriptions.push(
        vscode.window.registerCustomEditorProvider(VIEW_TYPE, new Provider(context), {
            webviewOptions: { retainContextWhenHidden: true },
            supportsMultipleEditorsPerDocument: true,
        }),
        vscode.commands.registerCommand('pdfZathura.openInZathura', uri => openInZathura(uri ?? activeUri)),
    );

    // set-accent.sh rewrites zathurarc on every theme change (often by
    // replacing it), so watch the directory, not the file.
    let timer = null;
    try {
        const w = fs.watch(configDir(), (_ev, name) => {
            if (name && name !== path.basename(zathurarcPath())) return;
            clearTimeout(timer);
            timer = setTimeout(() => panels.forEach(p => p.sendConfig()), 200);
        });
        context.subscriptions.push({ dispose: () => w.close() });
    } catch {
        // No zathura config dir: the viewer runs on zathura's defaults.
    }
};

exports.deactivate = () => {};
