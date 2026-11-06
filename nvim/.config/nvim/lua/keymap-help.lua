-- Space f k: every keymap, as   mode │ keys │ what it does │ what it runs
-- with a plain-English card in the preview (titles and descriptions from
-- lua/keymap-docs.lua; the technical desc / rhs goes in the "runs" column,
-- not the title). Replaces fzf-lua's own `keymaps` picker, whose title
-- column is the raw desc (":bprevious", "vim.lsp.buf.rename()" …).
--
--   Enter   try it (Normal-mode keys run; Visual ones on the last selection)
--   Ctrl-O  open the file where it's defined

local docs = require("keymap-docs")
local M = {}

local MODES = {
  { "n", "Normal", "blue" }, { "i", "Insert", "red" }, { "x", "Visual", "magenta" },
  { "s", "Select", "magenta" }, { "o", "Operator", "cyan" }, { "c", "Command", "yellow" },
  { "t", "Terminal", "green" },
}
local NAMES = {
  CR = "Enter", ESC = "Esc", BS = "Backspace", TAB = "Tab", SPACE = "Space", LEADER = "Space",
  UP = "↑", DOWN = "↓", LEFT = "←", RIGHT = "→", LT = "<", BAR = "|", BSLASH = "\\",
  DEL = "Delete", HOME = "Home", END = "End", PAGEUP = "PgUp", PAGEDOWN = "PgDn",
}
local MODS = { C = "Ctrl", S = "Shift", M = "Alt", A = "Alt", D = "Super" }

-- "<C-W>d" → "Ctrl+W d", " fk" → "Space f k"
local function pretty_key(tok)
  if tok == " " then return "Space" end
  local inner = tok:match("^<(.+)>$")
  if not inner then return tok end
  local parts = vim.split(inner, "-", { plain = true })
  local key = table.remove(parts)
  if key == "" then key = "-"; table.remove(parts) end
  local out = {}
  for _, m in ipairs(parts) do table.insert(out, MODS[m:upper()] or m) end
  key = NAMES[key:upper()] or (#key == 1 and #out > 0 and key:upper()) or key
  table.insert(out, key)
  return table.concat(out, "+")
end

function M.keys(lhs)
  local out, i = {}, 1
  while i <= #lhs do
    local tok
    if lhs:sub(i, i) == "<" then
      local j = lhs:find(">", i + 1, true)
      if j then tok = lhs:sub(i, j) end
    end
    tok = tok or lhs:match("^[%z\1-\127\194-\244][\128-\191]*", i)
    i = i + #tok
    table.insert(out, pretty_key(tok))
  end
  return table.concat(out, " ")
end

-- where a mapping was defined: path, line
local function source(d, mode)
  if d.callback then
    local info = debug.getinfo(d.callback, "S")
    local src = info and info.source and info.source:gsub("^@", "")
    if src and info.linedefined > 0 then
      if not src:find("^/") then src = vim.env.VIMRUNTIME .. "/lua/" .. src end   -- vim/_defaults.lua
      return src:gsub("%.lua%.lua$", ".lua"), info.linedefined
    end
  end
  local ok, out = pcall(vim.api.nvim_exec2, ("verbose %smap %s%s"):format(mode,
    d.buffer == 1 and "<buffer> " or "", vim.fn.keytrans(d.lhs)), { output = true })
  if not ok then return end
  local file, lnum = out.output:match("Last set from (.-) line (%d+)")
  if file then return vim.fs.normalize(file), tonumber(lnum) end
end

local function from_label(path)
  if not path then return "Neovim built-in" end
  local cfg = vim.fn.stdpath("config")
  if path:find("lazy/core/handler", 1, true) then return "Your config (lua/plugins.lua) · plugin loads on first use" end
  if path:sub(1, #cfg) == cfg then return "Your config" end
  local plug = path:match("/lazy/([^/]+)/")
  if plug then return "Plugin: " .. plug end
  return "Neovim built-in"
end

local function width(s) return vim.fn.strdisplaywidth(s) end
local function fit(s, n)
  if width(s) > n then s = vim.fn.strcharpart(s, 0, n - 1) .. "…" end
  return s .. string.rep(" ", n - width(s))
end

local rows = {}   -- "Normal\0Space f k" → row

local function collect()
  rows = {}
  local list, seen = {}, {}
  local buf = vim.api.nvim_get_current_buf()
  for _, m in ipairs(MODES) do
    for _, maps in ipairs({ vim.api.nvim_buf_get_keymap(buf, m[1]), vim.api.nvim_get_keymap(m[1]) }) do
      for _, d in ipairs(maps) do
        local k = m[1] .. "\0" .. d.lhs
        local dummy = not d.callback and (d.rhs or "") == ""
        if not seen[k] and not dummy and not d.lhs:find("^<Plug>") and not d.lhs:find("^<SNR>") then
          seen[k] = true
          local doc = docs.lookup(m[1], d.desc, d.rhs)
          local row = { mode = m, d = d, doc = doc, keys = M.keys(d.lhs) }
          rows[m[2] .. "\0" .. row.keys] = row
          table.insert(list, row)
        end
      end
    end
  end
  return list
end

local function line(mode, keys, title, runs)
  return ("%s │ %s │ %s │ %s"):format(mode, fit(keys, 13), fit(title, 36), runs)
end

local function row_of(selected)
  local s = require("fzf-lua.utils").strip_ansi_coloring(selected or "")
  local mode, keys = s:match("^%s*(%S+)%s*│%s*(.-)%s*│")
  return mode and rows[mode .. "\0" .. keys]
end

-- the preview: a card for the highlighted mapping
local function card(row)
  local doc, d = row.doc, row.d
  local path, lnum = source(d, row.mode[1])
  local l = { "# " .. doc.title, "" }
  if doc.about ~= "" then vim.list_extend(l, { doc.about, "" }) end
  table.insert(l, ("- **Keys:** `%s`  in %s mode%s"):format(row.keys, row.mode[2],
    d.buffer == 1 and " (this file only)" or ""))
  if doc.cmd ~= "" then table.insert(l, ("- **Runs:** `%s`"):format(doc.cmd)) end
  if doc.help ~= "" then table.insert(l, ("- **Help:** `:help %s`"):format(doc.help)) end
  local from = from_label(path)
  if path then
    local shown = path:sub(1, #vim.env.VIMRUNTIME) == vim.env.VIMRUNTIME
      and "$VIMRUNTIME" .. path:sub(#vim.env.VIMRUNTIME + 1) or vim.fn.fnamemodify(path, ":~")
    from = from .. ("  `%s:%d`"):format(shown, lnum)
  end
  table.insert(l, "- **From:** " .. from)
  return l
end

function M.open()
  local fzf = require("fzf-lua")
  local utils = require("fzf-lua.utils")
  local list = collect()
  local order = {}
  for i, m in ipairs(MODES) do order[m[1]] = i end
  table.sort(list, function(a, b)
    if a.mode ~= b.mode then return order[a.mode[1]] < order[b.mode[1]] end
    return a.keys < b.keys
  end)
  local entries = { line("mode    ", "keys", "what it does", "runs") }
  for _, r in ipairs(list) do
    local mode = utils.ansi_codes[r.mode[3]](fit(r.mode[2], 8))
    table.insert(entries, line(mode, r.keys, r.doc.title, utils.ansi_codes.grey(r.doc.cmd)))
  end

  local Card = require("fzf-lua.previewer.builtin").buffer_or_file:extend()
  function Card:parse_entry(entry_str)
    local row = row_of(entry_str)
    if not row then return {} end
    return { cache_key = false, filetype = "markdown", content = card(row),
             title = (" %s · %s "):format(row.mode[2], row.keys) }
  end
  function Card:gen_winopts()
    return vim.tbl_extend("force", self.winopts, { wrap = true, number = false,
      relativenumber = false, cursorline = false, conceallevel = 3 })
  end

  fzf.fzf_exec(entries, {
    prompt = "Shortcuts> ",
    previewer = { _ctor = function() return Card end },
    winopts = { title = " Keyboard shortcuts ", preview = { layout = "vertical", vertical = "down:30%" } },
    fzf_opts = { ["--header-lines"] = "1", ["--no-multi"] = true, ["--tiebreak"] = "index" },
    header = "Enter: try it  ·  Ctrl-O: open where it's defined",
    actions = {
      ["enter"] = function(selected)
        local row = row_of(selected[1])
        if not row then return end
        local m, lhs = row.mode[1], row.d.lhs
        if m == "n" or m == "x" then
          local keys = vim.api.nvim_replace_termcodes((m == "x" and "gv" or "") .. lhs, true, false, true)
          vim.api.nvim_feedkeys(keys, "m", false)
        else
          vim.notify(("%s works in %s mode: press %s there."):format(row.doc.title, row.mode[2], row.keys))
        end
      end,
      ["ctrl-o"] = function(selected)
        local row = row_of(selected[1])
        if not row then return end
        local path, lnum = source(row.d, row.mode[1])
        if path then vim.cmd(("edit +%d %s"):format(lnum, vim.fn.fnameescape(path)))
        else vim.notify("Built into Neovim (no Lua file to open).") end
      end,
    },
  })
end

return M
