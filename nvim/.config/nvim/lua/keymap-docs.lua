-- Plain-English names for Neovim's keymaps, shown by the Space f k picker
-- (lua/keymap-help.lua) and Settings › Keybindings › Neovim
-- (~/.config/hypr/settings-nvim-dump.lua).
--
-- Many mappings come with a technical `desc` (":bprevious",
-- "vim.lsp.buf.rename()", ":help Y-default", "blink.cmp: Select Next") or
-- none at all (matchit's %). Each entry here gives such a mapping
--   [1]   a title: what it does, in a few words
--   [2]   a description a person can understand
--   cmd   (optional) what it runs, when the desc / rhs doesn't say
-- The technical bit isn't thrown away: it's shown as "Runs" (and ":help …"
-- as "Help") next to the title.
--
-- Keys are tried in this order:  "<mode>:<desc>", "<desc>", "<mode>:<rhs>",
-- "<rhs>", then an entry whose title is the desc (a mapping of this config,
-- or one renamed in Settings with its name kept). Matching on the desc, not
-- the keys, keeps it right when a mapping is moved to other keys.
-- Modes: n normal, i insert, x visual, s select, o operator-pending, c command line.

local M = {}

local E = {
  -- ─── this config (desc = title) ──────────────────────────────────────────
  ["Choose Python environment"] = { "Choose Python environment",
    "Pick which virtualenv or conda environment the Python language server uses for this project.",
    cmd = ":PythonEnv" },
  ["Find files"] = { "Find files",
    "Fuzzy-search the files in this project by name and open one.", cmd = "FzfLua files" },
  ["Search text in project"] = { "Search text in project",
    "Type some text and see every line in the project that contains it.", cmd = "FzfLua live_grep" },
  ["Search word under cursor"] = { "Search word under cursor",
    "Find every place in the project where the word under the cursor appears.", cmd = "FzfLua grep_cword" },
  ["Switch between open files"] = { "Switch between open files",
    "List the files open in this Neovim and jump to one.", cmd = "FzfLua buffers" },
  ["Open a recent file"] = { "Open a recent file",
    "Pick from the files you opened recently, in any project.", cmd = "FzfLua oldfiles" },
  ["Search lines in this file"] = { "Search lines in this file",
    "Fuzzy-search the lines of the current file and jump to one.", cmd = "FzfLua blines" },
  ["Jump to a function or class"] = { "Jump to a function or class",
    "List the functions, classes and variables in this file (from the language server) and jump to one.",
    cmd = "FzfLua lsp_document_symbols" },
  ["List errors and warnings"] = { "List errors and warnings",
    "Show every error and warning in this file and jump to one.", cmd = "FzfLua diagnostics_document" },
  ["Search Neovim help"] = { "Search Neovim help",
    "Search Neovim's built-in manual by topic and open the page.", cmd = "FzfLua helptags" },
  ["Search keyboard shortcuts"] = { "Search keyboard shortcuts",
    "This list: every shortcut, what it does and what it runs. Enter tries the selected one.",
    cmd = "lua/keymap-help.lua" },
  ["Reopen last search"] = { "Reopen last search",
    "Bring back the last search list you used, with the same query.", cmd = "FzfLua resume" },
  ["n:Paste from clipboard"] = { "Paste from clipboard",
    "Paste text copied in other apps at the cursor (same as P)." },
  ["i:Paste from clipboard"] = { "Paste from clipboard",
    "Paste text copied in other apps where you're typing." },
  ["c:Paste from clipboard"] = { "Paste from clipboard",
    "Paste text copied in other apps into the : or / command line." },
  ["Format file"] = { "Format file",
    "Tidy the file's layout (indentation, spacing, line breaks) with the language server's formatter.",
    cmd = "vim.lsp.buf.format()" },
  ["Go to definition"] = { "Go to definition",
    "Jump to where the function, variable or class under the cursor is defined.",
    cmd = "vim.lsp.buf.definition()" },
  ["Go to declaration"] = { "Go to declaration",
    "Jump to where the thing under the cursor is declared (in C/C++, usually the header).",
    cmd = "vim.lsp.buf.declaration()" },

  -- ─── Neovim: language server (gr…, K, Ctrl+S) ────────────────────────────
  ["vim.lsp.buf.hover()"] = { "Show documentation",
    "Pop up the type and documentation of the thing under the cursor. Press again to move into the popup." },
  ["vim.lsp.buf.rename()"] = { "Rename everywhere",
    "Rename the variable, function or class under the cursor in every place it's used." },
  ["n:vim.lsp.buf.code_action()"] = { "Quick fixes and refactors",
    "Show what the language server can do here: fix this error, add a missing import, extract a function…" },
  ["x:vim.lsp.buf.code_action()"] = { "Quick fixes for selection",
    "Show fixes and refactorings the language server offers for the selected code." },
  ["vim.lsp.buf.references()"] = { "Find all uses",
    "List every place in the project that uses the thing under the cursor." },
  ["vim.lsp.buf.implementation()"] = { "Go to implementation",
    "Jump to the code that actually implements this interface or abstract method." },
  ["vim.lsp.buf.type_definition()"] = { "Go to type definition",
    "Jump to where the type of the variable under the cursor is defined." },
  ["vim.lsp.buf.document_symbol()"] = { "Outline of this file",
    "List the functions, classes and headings of this file in a side list (the location list)." },
  ["vim.lsp.buf.signature_help()"] = { "Show function parameters",
    "While typing a function call, pop up its parameters and what they mean." },

  -- ─── Neovim: errors and warnings ─────────────────────────────────────────
  ["Jump to the previous diagnostic in the current buffer"] = { "Previous error or warning",
    "Jump to the previous error, warning or hint in this file.", cmd = "vim.diagnostic.jump({ count = -1 })" },
  ["Jump to the next diagnostic in the current buffer"] = { "Next error or warning",
    "Jump to the next error, warning or hint in this file.", cmd = "vim.diagnostic.jump({ count = 1 })" },
  ["Jump to the first diagnostic in the current buffer"] = { "First error or warning",
    "Jump to the first error, warning or hint in this file.", cmd = "vim.diagnostic.jump({ count = -math.huge })" },
  ["Jump to the last diagnostic in the current buffer"] = { "Last error or warning",
    "Jump to the last error, warning or hint in this file.", cmd = "vim.diagnostic.jump({ count = math.huge })" },
  ["Show diagnostics under the cursor"] = { "Show error details",
    "Pop up the full error or warning message for the cursor's line.", cmd = "vim.diagnostic.open_float()" },

  -- ─── Neovim: editing ─────────────────────────────────────────────────────
  ["Add empty line above cursor"] = { "Add blank line above",
    "Insert an empty line above this one without leaving Normal mode (a count adds that many).",
    cmd = "vim._buf.space_above()" },
  ["Add empty line below cursor"] = { "Add blank line below",
    "Insert an empty line below this one without leaving Normal mode (a count adds that many).",
    cmd = "vim._buf.space_below()" },
  ["Toggle comment line"] = { "Comment / uncomment line",
    "Comment out the current line, or uncomment it (a count does that many lines).",
    cmd = "vim._comment.operator()" },
  ["n:Toggle comment"] = { "Comment / uncomment (+ motion)",
    "Comment or uncomment the lines a motion covers: gcip a paragraph, gc3j this line and 3 below.",
    cmd = "vim._comment.operator()" },
  ["x:Toggle comment"] = { "Comment / uncomment selection",
    "Comment out the selected lines, or uncomment them.", cmd = "vim._comment.operator()" },
  ["Comment textobject"] = { "Whole comment block",
    "After an operator, act on the comment block under the cursor: dgc deletes it, ygc copies it.",
    cmd = "vim._comment.textobject()" },
  ["n:Opens filepath or URI under cursor with the system handler (file explorer, web browser, …)"] = {
    "Open link or file", "Open the URL or file path under the cursor in its usual app (browser, file manager…).",
    cmd = "vim.ui.open()" },
  ["x:Opens filepath or URI under cursor with the system handler (file explorer, web browser, …)"] = {
    "Open selected link or path", "Open the selected URL or file path in its usual app.", cmd = "vim.ui.open()" },
  [":help Y-default"] = { "Copy to end of line",
    "Copy (yank) from the cursor to the end of the line, like D deletes to it." },
  [":help &-default"] = { "Repeat last replace",
    "Run the last :s find-and-replace again on this line, with the same options." },
  [":help CTRL-L-default"] = { "Clear search highlight",
    "Remove the highlighting left by a search, refresh diff colours and redraw the screen." },
  [":help i_CTRL-W-default"] = { "Delete word before cursor",
    "Delete the word just typed. It's a separate undo step, so u brings it back on its own." },
  [":help i_CTRL-U-default"] = { "Delete back to line start",
    "Delete everything typed before the cursor on this line. Undoable on its own." },
  [":help v_star-default"] = { "Search for selection",
    "Search forward for the selected text (like * does for a word).", cmd = "/<selection>" },
  [":help v_#-default"] = { "Search back for selection",
    "Search backward for the selected text (like # does for a word).", cmd = "?<selection>" },
  [":help v_@-default"] = { "Run a macro on each line",
    "With whole lines selected (V), press @ and a register to run that macro on every selected line." },
  [":help v_Q-default"] = { "Repeat last macro on each line",
    "With whole lines selected (V), replay the macro you recorded last on every selected line." },
  ["vim.snippet.jump if active, otherwise <Tab>"] = { "Next snippet field",
    "Inside an inserted snippet, jump to the next blank to fill in. Otherwise a normal Tab.",
    cmd = "vim.snippet.jump(1)" },
  ["vim.snippet.jump if active, otherwise <S-Tab>"] = { "Previous snippet field",
    "Inside an inserted snippet, jump back to the previous blank. Otherwise a normal Shift+Tab.",
    cmd = "vim.snippet.jump(-1)" },

  -- ─── Neovim: buffer / argument / tag / quickfix / location lists ─────────
  [":bprevious"] = { "Previous open file", "Switch to the previous file in the list of open files (buffers)." },
  [":bnext"] = { "Next open file", "Switch to the next file in the list of open files (buffers)." },
  [":brewind"] = { "First open file", "Switch to the first file in the list of open files (buffers)." },
  [":blast"] = { "Last open file", "Switch to the last file in the list of open files (buffers)." },
  [":previous"] = { "Previous file from command line",
    "Edit the previous file of the ones Neovim was started with (nvim a.py b.py …)." },
  [":next"] = { "Next file from command line",
    "Edit the next file of the ones Neovim was started with (nvim a.py b.py …)." },
  [":rewind"] = { "First file from command line", "Edit the first file Neovim was started with." },
  [":last"] = { "Last file from command line", "Edit the last file Neovim was started with." },
  [":tprevious"] = { "Previous tag match",
    "After jumping to a tag (Ctrl+]) that has several matches, go to the previous one." },
  [":tnext"] = { "Next tag match",
    "After jumping to a tag (Ctrl+]) that has several matches, go to the next one." },
  [":trewind"] = { "First tag match", "Go to the first of the matches for the last tag jump." },
  [":tlast"] = { "Last tag match", "Go to the last of the matches for the last tag jump." },
  [":ptprevious"] = { "Previous tag match (preview)", "Show the previous tag match in the preview window." },
  [":ptnext"] = { "Next tag match (preview)", "Show the next tag match in the preview window." },
  [":cprevious"] = { "Quickfix: previous result",
    "Jump to the previous entry of the quickfix list: search results, build errors (:grep, :make)." },
  [":cnext"] = { "Quickfix: next result",
    "Jump to the next entry of the quickfix list: search results, build errors (:grep, :make)." },
  [":crewind"] = { "Quickfix: first result", "Jump to the first entry of the quickfix list." },
  [":clast"] = { "Quickfix: last result", "Jump to the last entry of the quickfix list." },
  [":cpfile"] = { "Quickfix: previous file",
    "Jump to the quickfix list's entries in the previous file." },
  [":cnfile"] = { "Quickfix: next file", "Jump to the quickfix list's entries in the next file." },
  [":lprevious"] = { "Location list: previous result",
    "Jump to the previous entry of this window's location list (e.g. the file outline from gO)." },
  [":lnext"] = { "Location list: next result",
    "Jump to the next entry of this window's location list (e.g. the file outline from gO)." },
  [":lrewind"] = { "Location list: first result", "Jump to the first entry of this window's location list." },
  [":llast"] = { "Location list: last result", "Jump to the last entry of this window's location list." },
  [":lpfile"] = { "Location list: previous file",
    "Jump to the location list's entries in the previous file." },
  [":lnfile"] = { "Location list: next file", "Jump to the location list's entries in the next file." },

  -- ─── completion menu (blink.cmp) ─────────────────────────────────────────
  ["blink.cmp: Accept"] = { "Accept suggestion",
    "Insert the highlighted suggestion. With none highlighted, Enter just starts a new line." },
  ["blink.cmp: Select And Accept"] = { "Accept suggestion", "Insert the highlighted (or first) suggestion." },
  ["blink.cmp: Cancel"] = { "Close suggestions",
    "Close the suggestion menu and undo the suggestion being previewed." },
  ["blink.cmp: Hide"] = { "Close suggestions", "Close the suggestion menu (the key then works as usual)." },
  ["blink.cmp: Select Next"] = { "Next suggestion", "Move down in the suggestion menu." },
  ["blink.cmp: Select Prev"] = { "Previous suggestion", "Move up in the suggestion menu." },
  ["blink.cmp: <Custom Fn>, Select Prev"] = { "Previous suggestion", "Move up in the suggestion menu." },
  ["blink.cmp: Select Next, Snippet Forward"] = { "Next suggestion / snippet field",
    "Move down in the suggestion menu; inside a snippet, jump to the next blank. Otherwise a normal Tab." },
  ["blink.cmp: Select Prev, Snippet Backward"] = { "Previous suggestion / snippet field",
    "Move up in the suggestion menu; inside a snippet, jump to the previous blank." },
  ["blink.cmp: Show"] = { "Show suggestions", "Open the suggestion menu now." },
  ["blink.cmp: Show, Show Documentation, Hide Documentation"] = { "Show suggestions / docs",
    "Open the suggestion menu; when it's open, show or hide the docs of the highlighted item." },
  ["blink.cmp: Show Signature, Hide Signature"] = { "Toggle parameter hints",
    "Show or hide the popup with the parameters of the function call being typed." },
  ["blink.cmp: Scroll Documentation Up"] = { "Scroll docs popup up", "Scroll the suggestion's documentation up." },
  ["blink.cmp: Scroll Documentation Down"] = { "Scroll docs popup down",
    "Scroll the suggestion's documentation down." },
  ["blink.cmp: Show And Insert Or Accept Single, Select Next"] = { "Complete / next suggestion",
    "Complete the command: opens the menu and fills in the first match (or the only one); press again for the next." },
}

-- matchit (%, g%, [%, ]%, a%): no desc, keyed by their <Plug> rhs
local pairs_kw = "brackets, quotes and keyword pairs like if / else / end"
for _, m in ipairs({
  { "Normal", "Jump to", "" },
  { "Visual", "Select to", " (the selection grows to it)" },
  { "Operation", "Up to", " (after an operator: d%, y%, c%…)" },
}) do
  local kind, to, tail = m[1], m[2], m[3]
  E[("<Plug>(Matchit%sForward)"):format(kind)] = { to .. " matching pair",
    "Go to the partner of the bracket or keyword under the cursor: " .. pairs_kw .. tail .. "." }
  E[("<Plug>(Matchit%sBackward)"):format(kind)] = { to .. " matching pair, backward",
    "Like %, but cycles through if / else / end the other way" .. tail .. "." }
  E[("<Plug>(Matchit%sMultiBackward)"):format(kind)] = { to .. " start of block",
    "Back to the unmatched opening bracket or keyword (e.g. if) of the block the cursor is in" .. tail .. "." }
  E[("<Plug>(Matchit%sMultiForward)"):format(kind)] = { to .. " end of block",
    "Forward to the unmatched closing bracket or keyword (e.g. end) of the block the cursor is in" .. tail .. "." }
end
E["<Plug>(MatchitVisualTextObject)"] = { "Select matching block",
  "Select from a bracket or keyword to its partner, e.g. a whole if … end." }

M.entries = E

local by_title = {}
for _, e in pairs(E) do by_title[e[1]] = by_title[e[1]] or e end

local function technical(desc)
  return desc:match("^:") or desc:match("^vim%.") or desc:match("^blink%.cmp:")
end

-- mode, desc, rhs (nil / "" for a Lua callback) →
--   { title, about, cmd, help }   (cmd / help may be "")
function M.lookup(mode, desc, rhs)
  desc = vim.trim(desc or "")
  if rhs == "<Lua function>" then rhs = nil end
  local e = E[mode .. ":" .. desc] or E[desc]
    or (rhs and rhs ~= "" and (E[mode .. ":" .. rhs] or E[rhs])) or by_title[desc]
  local help = desc:match("^:help (.+)") or ""
  local cmd = e and e.cmd
    or (help == "" and technical(desc) and desc)
    or rhs or ""
  local title = e and e[1] or (desc ~= "" and desc) or rhs or ""
  return { title = title, about = e and e[2] or "", cmd = cmd, help = help }
end

return M
