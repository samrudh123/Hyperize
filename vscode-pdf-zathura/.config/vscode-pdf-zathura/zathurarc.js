// Reads zathurarc the way zathura does — `set`, `map`, `unmap`, `include`,
// quoting and # comments — so the viewer picks up the same colours, options
// and key remaps. set-accent.sh regenerates the file on every theme change;
// extension.js watches it and pushes the result to open viewers.
const fs = require('fs');
const os = require('os');
const path = require('path');

function configDir() {
    return path.join(process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config'), 'zathura');
}

function zathurarcPath() {
    return path.join(configDir(), 'zathurarc');
}

// Split a line into words: "double" and 'single' quotes group, backslash
// escapes, an unquoted # starts a comment.
function tokenize(line) {
    const out = [];
    let cur = null;
    let quote = null;
    for (let i = 0; i < line.length; i++) {
        const c = line[i];
        if (quote) {
            if (c === '\\' && i + 1 < line.length) cur += line[++i];
            else if (c === quote) quote = null;
            else cur += c;
        } else if (c === '"' || c === "'") {
            quote = c;
            cur ??= '';
        } else if (c === '\\' && i + 1 < line.length) {
            cur = (cur ?? '') + line[++i];
        } else if (c === '#' && cur === null) {
            break;
        } else if (/\s/.test(c)) {
            if (cur !== null) out.push(cur);
            cur = null;
        } else {
            cur = (cur ?? '') + c;
        }
    }
    if (cur !== null) out.push(cur);
    return out;
}

function expandHome(p) {
    return p.startsWith('~') ? path.join(os.homedir(), p.slice(1)) : p;
}

function parseFile(file, out, depth) {
    let text;
    try {
        text = fs.readFileSync(file, 'utf8');
    } catch {
        return;
    }
    for (const line of text.split('\n')) {
        const words = tokenize(line);
        if (!words.length) continue;
        const [cmd, ...args] = words;
        if (cmd === 'set' && args.length) {
            out.options[args[0]] = args.length > 1 ? args[1] : 'true';
        } else if (cmd === 'map' || cmd === 'unmap') {
            let mode = 'normal';
            if (args[0]?.startsWith('[') && args[0].endsWith(']')) mode = args.shift().slice(1, -1);
            if (!args.length) continue;
            out.maps.push(cmd === 'map'
                ? { mode, keys: args[0], fn: args[1] ?? null, arg: args[2] ?? null }
                : { mode, keys: args[0], fn: null, arg: null });
        } else if (cmd === 'include' && args.length && depth < 8) {
            parseFile(path.resolve(path.dirname(file), expandHome(args[0])), out, depth + 1);
        }
    }
}

function loadZathurarc() {
    const out = { options: {}, maps: [] };
    parseFile(zathurarcPath(), out, 0);
    return out;
}

module.exports = { configDir, zathurarcPath, loadZathurarc };
