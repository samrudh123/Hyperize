-- "rice" — Neovim in the desktop's colours.
--
-- Reads the same state the Quickshell shell does, so there is no template to
-- keep in sync with set-accent.sh:
--   ~/.config/hypr/theme/palette.json   the theme's 26 Catppuccin roles (set-theme.sh)
--   ~/.config/hypr/theme/accent         the accent hex (set-accent.sh, SUPER+ALT+C)
-- init.lua watches that directory and re-runs `:colorscheme rice` when either
-- changes, so open editors recolour live.
--
-- Like the rest of the rice, the ACCENT goes on UI (cursor line number, mode,
-- selection, search, menus, borders) and syntax stays on the theme's own roles
-- — keywords are mauve, strings green, … whatever the accent is.

local dir = vim.fn.expand("~/.config/hypr/theme")

local function read(path)
  local f = io.open(path)
  if not f then return nil end
  local s = f:read("a")
  f:close()
  return s
end

-- Catppuccin Mocha, for a machine without the theme state
local p = {
  rosewater = "#f5e0dc", flamingo = "#f2cdcd", pink = "#f5c2e7", mauve = "#cba6f7",
  red = "#f38ba8", maroon = "#eba0ac", peach = "#fab387", yellow = "#f9e2af",
  green = "#a6e3a1", teal = "#94e2d5", sky = "#89dceb", sapphire = "#74c7ec",
  blue = "#89b4fa", lavender = "#b4befe", text = "#cdd6f4", subtext1 = "#bac2de",
  subtext0 = "#a6adc8", overlay2 = "#9399b2", overlay1 = "#7f849c", overlay0 = "#6c7086",
  surface2 = "#585b70", surface1 = "#45475a", surface0 = "#313244", base = "#1e1e2e",
  mantle = "#181825", crust = "#11111b", accent = "mauve",
}
local ok, json = pcall(vim.json.decode, read(dir .. "/palette.json") or "")
if ok and type(json) == "table" and json.base then p = json end

local hex = (read(dir .. "/accent") or ""):match("^%s*#?(%x%x%x%x%x%x)")
local A = hex and ("#" .. hex:lower()) or p[p.accent or "mauve"] or p.mauve

-- fg mixed over bg, a = share of fg
local function blend(fg, bg, a)
  local out = "#"
  for i = 2, 6, 2 do
    local f, b = tonumber(fg:sub(i, i + 1), 16), tonumber(bg:sub(i, i + 1), 16)
    out = out .. string.format("%02x", math.floor(f * a + b * (1 - a) + 0.5))
  end
  return out
end

vim.cmd("highlight clear")
if vim.g.syntax_on then vim.cmd("syntax reset") end
vim.o.background = "dark"
vim.g.colors_name = "rice"

local NONE = "NONE"
local hl = {
  -- editor UI. Normal has no background: Ghostty is translucent + blurred,
  -- and the editor keeps that glass instead of painting a solid slab over it.
  Normal       = { fg = p.text, bg = NONE },
  NormalNC     = { link = "Normal" },
  NormalFloat  = { fg = p.text, bg = p.mantle },
  FloatBorder  = { fg = A, bg = p.mantle },
  FloatTitle   = { fg = A, bg = p.mantle, bold = true },
  CursorLine   = { bg = blend(p.surface0, p.base, 0.55) },
  CursorColumn = { link = "CursorLine" },
  ColorColumn  = { bg = p.surface0 },
  CursorLineNr = { fg = A, bold = true },
  LineNr       = { fg = p.surface2 },
  SignColumn   = { bg = NONE },
  FoldColumn   = { fg = p.overlay0 },
  Folded       = { fg = p.overlay2, bg = p.surface0 },
  Visual       = { bg = blend(A, p.base, 0.28) },
  VisualNOS    = { link = "Visual" },
  Search       = { fg = p.text, bg = blend(A, p.base, 0.40) },
  IncSearch    = { fg = p.crust, bg = A, bold = true },
  CurSearch    = { link = "IncSearch" },
  Substitute   = { fg = p.crust, bg = p.red },
  MatchParen   = { fg = p.peach, bg = p.surface1, bold = true },
  Pmenu        = { fg = p.overlay2, bg = p.mantle },
  PmenuSel     = { fg = p.text, bg = blend(A, p.base, 0.32), bold = true },
  PmenuSbar    = { bg = p.surface0 },
  PmenuThumb   = { bg = A },
  PmenuMatch   = { fg = A, bold = true },
  StatusLine   = { fg = p.subtext1, bg = p.mantle },
  StatusLineNC = { fg = p.overlay0, bg = p.mantle },
  TabLine      = { fg = p.overlay0, bg = p.mantle },
  TabLineFill  = { bg = NONE },
  TabLineSel   = { fg = A, bg = p.surface0, bold = true },
  WinBar       = { fg = p.text, bold = true },
  WinBarNC     = { fg = p.overlay0 },
  WinSeparator = { fg = p.surface1 },
  NonText      = { fg = p.surface1 },
  Whitespace   = { fg = p.surface1 },
  SpecialKey   = { fg = p.surface2 },
  EndOfBuffer  = { fg = p.surface1 },
  Conceal      = { fg = p.overlay1 },
  Directory    = { fg = A },
  Title        = { fg = A, bold = true },
  Question     = { fg = A },
  MoreMsg      = { fg = A },
  ModeMsg      = { fg = p.text, bold = true },
  ErrorMsg     = { fg = p.red, bold = true },
  WarningMsg   = { fg = p.yellow },
  QuickFixLine = { bg = p.surface1, bold = true },
  WildMenu     = { link = "PmenuSel" },

  -- statusline mode pill (init.lua)
  RiceMode     = { fg = p.crust, bg = A, bold = true },
  RiceModeEdge = { fg = A, bg = p.mantle },
  RiceFile     = { fg = p.text, bg = p.mantle, bold = true },
  RiceMod      = { fg = p.peach, bg = p.mantle, bold = true },

  -- plugins: fzf-lua (fzf_colors = true reads these), blink.cmp, lazy, mason
  FzfLuaTitle         = { link = "FloatTitle" },
  FzfLuaFzfMatch      = { fg = A, bold = true },
  FzfLuaFzfPrompt     = { fg = A, bold = true },
  FzfLuaFzfPointer    = { fg = A },
  FzfLuaFzfMarker     = { fg = p.peach },
  FzfLuaFzfCursorLine = { fg = p.text, bg = blend(A, p.base, 0.22) },
  FzfLuaFzfInfo       = { fg = p.overlay1 },
  FzfLuaFzfSeparator  = { fg = p.surface1 },
  FzfLuaFzfScrollbar  = { fg = A },
  BlinkCmpMenuBorder          = { link = "FloatBorder" },
  BlinkCmpDocBorder           = { link = "FloatBorder" },
  BlinkCmpSignatureHelpBorder = { link = "FloatBorder" },
  BlinkCmpLabelMatch          = { fg = A, bold = true },
  BlinkCmpLabelDeprecated     = { fg = p.overlay0, strikethrough = true },
  BlinkCmpKind                = { fg = p.mauve },
  BlinkCmpSource              = { fg = p.overlay0 },
  LazyH1          = { fg = p.crust, bg = A, bold = true },
  LazyButtonActive = { link = "LazyH1" },
  LazySpecial     = { fg = A },
  MasonHeader     = { fg = p.crust, bg = A, bold = true },
  MasonHighlight  = { fg = A },
  MasonHighlightBlockBold = { fg = p.crust, bg = A, bold = true },
  MasonMutedBlock = { fg = p.overlay1, bg = p.surface0 },

  -- diff / spelling / diagnostics
  DiffAdd      = { bg = blend(p.green, p.base, 0.20) },
  DiffChange   = { bg = blend(p.blue, p.base, 0.13) },
  DiffDelete   = { fg = p.red, bg = blend(p.red, p.base, 0.20) },
  DiffText     = { bg = blend(p.blue, p.base, 0.30) },
  Added        = { fg = p.green },
  Changed      = { fg = p.yellow },
  Removed      = { fg = p.red },
  SpellBad     = { sp = p.red, undercurl = true },
  SpellCap     = { sp = p.yellow, undercurl = true },
  SpellRare    = { sp = p.green, undercurl = true },
  SpellLocal   = { sp = p.blue, undercurl = true },
  DiagnosticError = { fg = p.red },
  DiagnosticWarn  = { fg = p.yellow },
  DiagnosticInfo  = { fg = p.sky },
  DiagnosticHint  = { fg = p.teal },
  DiagnosticOk    = { fg = p.green },
  DiagnosticUnderlineError = { sp = p.red, undercurl = true },
  DiagnosticUnderlineWarn  = { sp = p.yellow, undercurl = true },
  DiagnosticUnderlineInfo  = { sp = p.sky, undercurl = true },
  DiagnosticUnderlineHint  = { sp = p.teal, undercurl = true },
  DiagnosticVirtualTextError = { fg = p.red, bg = blend(p.red, p.base, 0.10) },
  DiagnosticVirtualTextWarn  = { fg = p.yellow, bg = blend(p.yellow, p.base, 0.10) },
  DiagnosticVirtualTextInfo  = { fg = p.sky, bg = blend(p.sky, p.base, 0.10) },
  DiagnosticVirtualTextHint  = { fg = p.teal, bg = blend(p.teal, p.base, 0.10) },
  LspReferenceText  = { bg = p.surface1 },
  LspReferenceRead  = { bg = p.surface1 },
  LspReferenceWrite = { bg = p.surface1 },
  LspInlayHint      = { fg = p.overlay0, bg = blend(p.surface0, p.base, 0.5) },

  -- syntax (Catppuccin's role mapping)
  Comment      = { fg = p.overlay2, italic = true },
  Constant     = { fg = p.peach },
  String       = { fg = p.green },
  Character    = { fg = p.teal },
  Number       = { fg = p.peach },
  Float        = { fg = p.peach },
  Boolean      = { fg = p.peach },
  Identifier   = { fg = p.flamingo },
  Function     = { fg = p.blue },
  Statement    = { fg = p.mauve },
  Conditional  = { fg = p.mauve },
  Repeat       = { fg = p.mauve },
  Label        = { fg = p.sapphire },
  Operator     = { fg = p.sky },
  Keyword      = { fg = p.mauve },
  Exception    = { fg = p.mauve },
  PreProc      = { fg = p.pink },
  Include      = { fg = p.mauve },
  Define       = { fg = p.pink },
  Macro        = { fg = p.mauve },
  PreCondit    = { fg = p.pink },
  Type         = { fg = p.yellow },
  StorageClass = { fg = p.yellow },
  Structure    = { fg = p.yellow },
  Typedef      = { fg = p.yellow },
  Special      = { fg = p.pink },
  SpecialChar  = { fg = p.pink },
  Tag          = { fg = p.lavender },
  Delimiter    = { fg = p.overlay2 },
  SpecialComment = { fg = p.overlay1, italic = true },
  Underlined   = { underline = true },
  Error        = { fg = p.red },
  Todo         = { fg = p.base, bg = p.yellow, bold = true },

  -- treesitter
  ["@variable"]           = { fg = p.text },
  ["@variable.builtin"]   = { fg = p.red },
  ["@variable.parameter"] = { fg = p.maroon },
  ["@variable.member"]    = { fg = p.lavender },
  ["@property"]           = { fg = p.lavender },
  ["@module"]             = { fg = p.lavender },
  ["@constant"]           = { fg = p.peach },
  ["@constant.builtin"]   = { fg = p.peach },
  ["@string"]             = { fg = p.green },
  ["@string.escape"]      = { fg = p.pink },
  ["@string.regexp"]      = { fg = p.pink },
  ["@string.special.url"] = { fg = p.rosewater, underline = true },
  ["@character"]          = { fg = p.teal },
  ["@number"]             = { fg = p.peach },
  ["@boolean"]            = { fg = p.peach },
  ["@type"]               = { fg = p.yellow },
  ["@type.builtin"]       = { fg = p.yellow },
  ["@attribute"]          = { fg = p.yellow },
  ["@function"]           = { fg = p.blue },
  ["@function.builtin"]   = { fg = p.peach },
  ["@function.method"]    = { fg = p.blue },
  ["@constructor"]        = { fg = p.sapphire },
  ["@operator"]           = { fg = p.sky },
  ["@keyword"]            = { fg = p.mauve },
  ["@punctuation"]        = { fg = p.overlay2 },
  ["@punctuation.special"] = { fg = p.sky },
  ["@comment"]            = { link = "Comment" },
  ["@tag"]                = { fg = p.mauve },
  ["@tag.attribute"]      = { fg = p.teal },
  ["@tag.delimiter"]      = { fg = p.sky },
  ["@markup.heading.1"]   = { fg = p.red, bold = true },
  ["@markup.heading.2"]   = { fg = p.peach, bold = true },
  ["@markup.heading.3"]   = { fg = p.yellow, bold = true },
  ["@markup.heading.4"]   = { fg = p.green, bold = true },
  ["@markup.heading.5"]   = { fg = p.sapphire, bold = true },
  ["@markup.heading.6"]   = { fg = p.lavender, bold = true },
  ["@markup.strong"]      = { bold = true },
  ["@markup.italic"]      = { italic = true },
  ["@markup.strikethrough"] = { strikethrough = true },
  ["@markup.link"]        = { fg = A },
  ["@markup.link.url"]    = { fg = p.rosewater, underline = true },
  ["@markup.raw"]         = { fg = p.teal },
  ["@markup.list"]        = { fg = p.sky },
  ["@markup.quote"]       = { fg = p.overlay2, italic = true },
  ["@diff.plus"]          = { fg = p.green },
  ["@diff.minus"]         = { fg = p.red },
  ["@diff.delta"]         = { fg = p.yellow },
}
for name, spec in pairs(hl) do vim.api.nvim_set_hl(0, name, spec) end

-- :terminal uses the theme's ANSI colours too
local ansi = { p.surface1, p.red, p.green, p.yellow, p.blue, p.pink, p.teal, p.subtext1,
               p.surface2, p.red, p.green, p.yellow, p.blue, p.pink, p.teal, p.subtext0 }
for i, c in ipairs(ansi) do vim.g["terminal_color_" .. (i - 1)] = c end
