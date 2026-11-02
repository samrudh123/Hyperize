#!/usr/bin/python3 -I
"""yazi-style preview for fzf — `fzf-preview.py PATH`.

Used by yazi's `z` (recursive fuzzy find): yazi-live.sh adds it to
FZF_DEFAULT_OPTS for the fzf that yazi starts.

What yazi's preview pane would show for PATH, drawn in fzf's preview window:

  folder        its entries, hidden ones included, folders first, with icons (eza)
  markdown      rendered by glow                       (plugins/md.yazi)
  text / code   highlighted by bat — same recoloured Catppuccin Mocha as yazi
  image         the picture itself
  PDF           page 1 recoloured like zathura, with zathura's statusbar
                (plugins/zathura-pdf.yazi's recolor.py, so it follows the accent)
  video         a frame from ~10% in, plus the length
  archive       the file list
  anything else (executables, .so, fonts, audio …) a file-info card from
                `file` instead of binary junk

Pictures use the kitty graphics protocol's unicode placeholders, which fzf
passes through as ordinary text (Ghostty supports them). Rendered pictures are
cached in ~/.cache/fzf-preview, keyed by path + mtime + size + box size (and
zathurarc's mtime for PDFs, so an accent change re-renders them).
"""
import base64
import fcntl
import hashlib
import os
import shutil
import struct
import subprocess
import sys
import termios
import time
from pathlib import Path

HOME = Path.home()
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config")
CACHE = Path(os.environ.get("XDG_CACHE_HOME") or HOME / ".cache") / "fzf-preview"
ZATHURARC = CONFIG / "zathura" / "zathurarc"
RECOLOR = Path(__file__).resolve().parent / "plugins" / "zathura-pdf.yazi" / "recolor.py"
BAT = shutil.which("batcat") or shutil.which("bat")

COLS = int(os.environ.get("FZF_PREVIEW_COLUMNS") or 80)
LINES = int(os.environ.get("FZF_PREVIEW_LINES") or 24)

ACCENT = "\x1b[38;5;53m"     # zshrc's accent slot (follows the accent live)
DIM = "\x1b[38;5;245m"
RESET = "\x1b[0m"

# kitty unicode placeholders: U+10EEEE, then one diacritic for the row and one
# for the column (kitty's gen/rowcolumn-diacritics.txt, in order)
PLACEHOLDER = "\U0010EEEE"
IMAGE_ID = 0x5F2A71          # fixed: each preview replaces the previous picture
DIACRITICS = [chr(int(h, 16)) for h in (
    "0305 030D 030E 0310 0312 033D 033E 033F 0346 034A 034B 034C 0350 0351 0352 0357 "
    "035B 0363 0364 0365 0366 0367 0368 0369 036A 036B 036C 036D 036E 036F 0483 0484 "
    "0485 0486 0487 0592 0593 0594 0595 0597 0598 0599 059C 059D 059E 059F 05A0 05A1 "
    "05A8 05A9 05AB 05AC 05AF 05C4 0610 0611 0612 0613 0614 0615 0616 0617 0657 0658 "
    "0659 065A 065B 065D 065E 06D6 06D7 06D8 06D9 06DA 06DB 06DC 06DF 06E0 06E1 06E2 "
    "06E4 06E7 06E8 06EB 06EC 0730 0732 0733 0735 0736 073A 073D 073F 0740 0741 0743 "
    "0745 0747 0749 074A 07EB 07EC 07ED 07EE 07EF 07F0 07F1 07F3 0816 0817 0818 0819 "
    "081B 081C 081D 081E 081F 0820 0821 0822 0823 0825 0826 0827 0829 082A 082B 082C "
    "082D 0951 0953 0954 0F82 0F83 0F86 0F87 135D 135E 135F 17DD 193A 1A17 1A75 1A76 "
    "1A77 1A78 1A79 1A7A 1A7B 1A7C 1B6B 1B6D 1B6E 1B6F 1B70 1B71 1B72 1B73 1CD0 1CD1 "
    "1CD2 1CDA 1CDB 1CE0 1DC0 1DC1 1DC3 1DC4 1DC5 1DC6 1DC7 1DC8 1DC9 1DCB 1DCC 1DD1 "
    "1DD2 1DD3 1DD4 1DD5 1DD6 1DD7 1DD8 1DD9 1DDA 1DDB 1DDC 1DDD 1DDE 1DDF 1DE0 1DE1 "
    "1DE2 1DE3 1DE4 1DE5 1DE6 1DFE 20D0 20D1 20D4 20D5 20D6 20D7 20DB 20DC 20E1 20E7 "
    "20E9 20F0 2CEF 2CF0 2CF1 2DE0 2DE1 2DE2 2DE3 2DE4 2DE5 2DE6 2DE7 2DE8 2DE9 2DEA "
    "2DEB 2DEC 2DED 2DEE 2DEF 2DF0 2DF1 2DF2 2DF3 2DF4 2DF5 2DF6 2DF7 2DF8 2DF9 2DFA "
    "2DFB 2DFC 2DFD 2DFE 2DFF A66F A67C A67D A6F0 A6F1 A8E0 A8E1 A8E2 A8E3 A8E4 A8E5 "
    "A8E6 A8E7 A8E8 A8E9 A8EA A8EB A8EC A8ED A8EE A8EF A8F0 A8F1 AAB0 AAB2 AAB3 AAB7 "
    "AAB8 AABE AABF AAC1 FE20 FE21 FE22 FE23 FE24 FE25 FE26 10A0F 10A38 1D185 1D186 1D187 "
    "1D188 1D189 1D1AA 1D1AB 1D1AC 1D1AD 1D242 1D243 1D244 "
).split()]


def out(s):
    sys.stdout.write(s)


def human(n):
    for unit in ("B", "K", "M", "G", "T"):
        if n < 1024 or unit == "T":
            return f"{n:.0f}{unit}" if unit == "B" else f"{n:.1f}{unit}"
        n /= 1024


def run(*cmd, **kw):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=10, **kw).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def cell_size():
    try:
        fd = os.open("/dev/tty", os.O_RDONLY)
        r, c, xp, yp = struct.unpack("HHHH", fcntl.ioctl(fd, termios.TIOCGWINSZ, b"\0" * 8))
        os.close(fd)
        if xp and yp and r and c:
            return xp / c, yp / r
    except OSError:
        pass
    return 10.0, 21.0


def cache_path(p, tag, *extra):
    st = p.stat()
    key = f"{p.resolve()}\0{st.st_mtime_ns}\0{st.st_size}\0{tag}\0" + "\0".join(map(str, extra))
    CACHE.mkdir(parents=True, exist_ok=True)
    return CACHE / (hashlib.sha1(key.encode()).hexdigest() + ".png")


# ── pictures ────────────────────────────────────────────────────────────────

def show_png(png, rows):
    """Draw PNG fitted into COLS x rows cells (never enlarged), top-left."""
    from PIL import Image
    cw, ch = cell_size()
    with Image.open(png) as im:
        w, h = im.size
    scale = min(COLS * cw / w, rows * ch / h, 1.0)
    c = max(1, min(COLS, round(w * scale / cw)))
    r = max(1, min(rows, round(h * scale / ch)))
    r = min(r, len(DIACRITICS))
    c = min(c, len(DIACRITICS))
    path = base64.b64encode(str(png).encode()).decode()
    out(f"\x1b_Ga=T,U=1,t=f,f=100,i={IMAGE_ID},c={c},r={r},q=2;{path}\x1b\\")
    color = f"\x1b[38;2;{IMAGE_ID >> 16 & 255};{IMAGE_ID >> 8 & 255};{IMAGE_ID & 255}m"
    rows_out = []
    for y in range(r):
        rows_out.append(color + "".join(PLACEHOLDER + DIACRITICS[y] + DIACRITICS[x] for x in range(c)) + "\x1b[39m")
    out("\n".join(rows_out))
    return r


def fit_png(src, dst, rows):
    """Downscale an image file into a PNG no bigger than the preview box."""
    from PIL import Image, ImageOps
    cw, ch = cell_size()
    with Image.open(src) as im:
        im = ImageOps.exif_transpose(im)
        im.thumbnail((int(COLS * cw), int(rows * ch)))
        if im.mode not in ("RGB", "RGBA", "L", "LA"):
            im = im.convert("RGBA")
        tmp = dst.with_suffix(f".{os.getpid()}.png")
        im.save(tmp, "PNG", compress_level=1)
        os.replace(tmp, dst)


def preview_image(p):
    dst = cache_path(p, "img", COLS, LINES)
    if not dst.exists():
        try:
            fit_png(p, dst, LINES - 1)
        except Exception as e:
            return info(p, note=f"can't decode: {e}")
    try:
        from PIL import Image
        with Image.open(p) as im:
            dims = f"{im.size[0]}×{im.size[1]}"
    except Exception:
        dims = ""
    show_png(dst, LINES - 1)
    out(f"\n{DIM}{dims}  {human(p.stat().st_size)}{RESET}")


def zathura_statusbar():
    bg, fg = "#000000", "#ffffff"
    try:
        for line in ZATHURARC.read_text().splitlines():
            w = line.split()
            if len(w) >= 3 and w[0] == "set" and w[1] in ("statusbar-bg", "statusbar-fg"):
                v = w[2].strip('"')
                if w[1] == "statusbar-bg":
                    bg = v
                else:
                    fg = v
    except OSError:
        pass

    def sgr(hexstr, base):
        h = hexstr.lstrip("#")
        try:
            return f"\x1b[{base};2;{int(h[0:2], 16)};{int(h[2:4], 16)};{int(h[4:6], 16)}m"
        except ValueError:
            return ""
    return sgr(bg, 48), sgr(fg, 38)


def preview_pdf(p):
    try:
        zstamp = ZATHURARC.stat().st_mtime_ns
    except OSError:
        zstamp = 0
    rows = LINES - 1
    dst = cache_path(p, "pdf", COLS, LINES, zstamp)
    if not dst.exists():
        cw, ch = cell_size()
        tmp = dst.with_suffix(f".{os.getpid()}")
        subprocess.run(["pdftoppm", "-f", "1", "-l", "1", "-singlefile", "-png",
                        "-scale-to", str(int(max(COLS * cw, rows * ch))), str(p), str(tmp)],
                       capture_output=True, timeout=20)
        png, jpg = Path(f"{tmp}.png"), Path(f"{tmp}.jpg")
        if not png.exists():
            return info(p, note="pdftoppm couldn't render it (encrypted or damaged?)")
        if RECOLOR.exists():
            subprocess.run(["/usr/bin/python3", str(RECOLOR), str(png), str(jpg), "90"], capture_output=True)
        src = jpg if jpg.exists() else png
        try:
            fit_png(src, dst, rows)
        finally:
            for f in (png, jpg):
                f.unlink(missing_ok=True)
    shown = show_png(dst, rows)
    pages = next((l.split(":", 1)[1].strip() for l in run("pdfinfo", str(p)).splitlines()
                  if l.startswith("Pages:")), "?")
    bg, fg = zathura_statusbar()
    left, right = f" {p.name}", f"[1/{pages}] "
    width = COLS - 1          # a line exactly as wide as the window counts as overflow
    pad = max(1, width - len(left) - len(right))
    if len(left) + len(right) + 1 > width:
        left = left[:max(1, width - len(right) - 2)] + "…"
        pad = 1
    out("\n" * (rows - shown + 1) + f"{bg}{fg}{left}{' ' * pad}{right}{RESET}")


def preview_video(p):
    dur = run("ffprobe", "-v", "error", "-show_entries", "format=duration",
              "-of", "default=nw=1:nk=1", str(p)).strip()
    try:
        secs = float(dur)
    except ValueError:
        secs = 0.0
    dst = cache_path(p, "vid", COLS, LINES)
    if not dst.exists():
        tmp = dst.with_suffix(f".{os.getpid()}.png")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", f"{secs * 0.1:.2f}", "-i", str(p),
                        "-frames:v", "1", str(tmp)], capture_output=True, timeout=20)
        if not tmp.exists():
            return info(p)
        try:
            fit_png(tmp, dst, LINES - 1)
        finally:
            tmp.unlink(missing_ok=True)
    show_png(dst, LINES - 1)
    t = time.strftime("%H:%M:%S" if secs >= 3600 else "%M:%S", time.gmtime(secs))
    out(f"\n{DIM}{t}  {human(p.stat().st_size)}{RESET}")


# ── text ────────────────────────────────────────────────────────────────────

def preview_dir(p):
    listing = run("eza", "-1a", "--icons=always", "--color=always", "--group-directories-first",
                  "--no-quotes", str(p))
    lines = listing.splitlines()
    if not lines:
        out(f"{DIM}  (empty folder){RESET}" if os.access(p, os.R_OK) else f"{DIM}  (no permission){RESET}")
        return
    out("\n".join(lines[:LINES]))


def preview_text(p):
    if p.suffix.lower() in (".md", ".markdown", ".mdx") and shutil.which("glow"):
        r = subprocess.run(["glow", "--style", "dark", "--width", str(COLS), str(p)],
                           capture_output=True, text=True, env={**os.environ, "CLICOLOR_FORCE": "1"})
        if r.returncode == 0 and r.stdout.strip():
            out("\n".join(r.stdout.splitlines()[:LINES]))
            return
    if BAT:
        os.execv(BAT, [BAT, "--color=always", "--style=plain", "--paging=never", "--wrap=never",
                       "--tabs=2", f"--line-range=:{LINES}", str(p)])
    with open(p, errors="replace") as f:
        out("".join(f.readline() for _ in range(LINES)))


def preview_archive(p):
    raw = run("7z", "l", "-ba", "-slt", str(p))
    items, cur = [], {}
    for line in raw.splitlines() + [""]:
        if not line.strip():
            if "Path" in cur:
                items.append(cur)
            cur = {}
        elif " = " in line:
            k, v = line.split(" = ", 1)
            cur[k] = v
    if not items:
        return info(p)
    width = COLS - 9
    rows = []
    for it in items[:LINES]:
        folder = it.get("Folder") == "+" or it.get("Attributes", "").startswith("D")
        name = it["Path"] + ("/" if folder else "")
        name = name if len(name) <= width else "…" + name[-(width - 1):]
        size = "" if folder else human(int(it.get("Size") or 0))
        color = ACCENT if folder else ""
        rows.append(f"{color}{name}{RESET}{' ' * max(1, COLS - len(name) - len(size))}{DIM}{size}{RESET}")
    out("\n".join(rows))


def info(p, note=None):
    """yazi's fallback for files it can't show: what `file` says, plus stat."""
    st = p.stat()
    desc = run("file", "-bL", str(p)).strip() or "unknown"
    mime = run("file", "-bL", "--mime-type", str(p)).strip()
    perms = run("stat", "-c", "%A", str(p)).strip()
    icon = "\uf15b"                             # nf-fa-file
    if os.access(p, os.X_OK):
        icon = "\uf489"                         # nf-oct-terminal
    out(f"{ACCENT}{icon}  {p.name}{RESET}\n\n")
    label_w = 10
    body_w = max(20, COLS - label_w - 1)

    def row(label, value):
        words, line, first = value.split(", ") if label == "Type" else [value], "", True
        chunks = []
        for wd in words:
            piece = wd if not line else line + ", " + wd
            if len(piece) > body_w and line:
                chunks.append(line + ",")
                line = wd
            else:
                line = piece
        chunks.append(line)
        for c in chunks:
            out(f"{ACCENT}{label if first else '':<{label_w}}{RESET}{c}\n")
            first = False

    row("Type", desc)
    if mime:
        row("MIME", mime)
    row("Size", f"{human(st.st_size)}  ({st.st_size:,} bytes)")
    row("Modified", time.strftime("%Y-%m-%d %H:%M", time.localtime(st.st_mtime)))
    row("Perms", perms)
    if note:
        out(f"\n{DIM}{note}{RESET}")


# ── dispatch ────────────────────────────────────────────────────────────────

ARCHIVES = ("application/zip", "application/x-tar", "application/gzip", "application/x-xz",
            "application/x-bzip2", "application/x-7z-compressed", "application/vnd.rar",
            "application/x-rar", "application/zstd", "application/java-archive",
            "application/x-compressed-tar", "application/vnd.debian.binary-package",
            "application/x-rpm", "application/x-iso9660-image")


def main():
    if len(sys.argv) < 2:
        return
    p = Path(os.path.expanduser(sys.argv[1]))
    if p.is_symlink() and not p.exists():
        out(f"{ACCENT}\U000f0338  {p.name}{RESET}\n\nbroken link → {os.readlink(p)}")
        return
    if not p.exists():
        return
    if p.is_dir():
        return preview_dir(p)
    if not p.is_file():
        return info(p)
    if p.stat().st_size == 0:
        out(f"{DIM}  (empty file){RESET}")
        return

    mime = run("file", "-bL", "--mime", str(p)).strip()
    kind, _, charset = mime.partition("; charset=")
    try:
        if kind == "application/pdf":
            return preview_pdf(p)
        if kind.startswith("image/") and kind != "image/svg+xml":
            return preview_image(p)
        if kind.startswith("video/"):
            return preview_video(p)
        if kind in ARCHIVES:
            return preview_archive(p)
        if charset and charset != "binary":
            return preview_text(p)
    except Exception as e:                      # anything odd: the info card
        out(RESET + "\n")
        return info(p, note=f"preview failed: {e}")
    info(p)


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        pass
    finally:
        try:
            sys.stdout.flush()
        except BrokenPipeError:
            pass
