-- Neovim config (starter). Yazi's "edit" opener launches nvim (yazi/yazi.toml).

local o = vim.opt

-- y / p go through the system clipboard (wl-copy / wl-paste under Wayland),
-- so yanked text pastes into other apps and vice versa.
o.clipboard = "unnamedplus"

o.number = true
o.mouse = "a"
o.termguicolors = true
o.ignorecase = true          -- /search is case-insensitive…
o.smartcase = true           -- …unless it has a capital letter
o.expandtab = true
o.shiftwidth = 4
o.tabstop = 4
o.scrolloff = 5
o.undofile = true            -- undo history survives closing the file
o.cursorline = true
o.showmode = false           -- the statusline shows the mode
o.signcolumn = "yes"         -- room for diagnostics without the text jumping
o.winborder = "rounded"      -- hover / signature / diagnostic popups
o.updatetime = 300
o.splitbelow = true          -- :split opens the new window below (e.g. :split | terminal)

vim.g.mapleader = " "        -- Space; set before plugins so their keys use it
vim.g.maplocalleader = " "

-- ─── Theme: follows the desktop's theme + accent (colors/rice.lua) ─────────
vim.cmd.colorscheme("rice")

require("plugins")           -- file finder, completion, language servers

-- ─── LSP ──────────────────────────────────────────────────────────────────
-- Neovim's own defaults already cover most of it: K hover, grn rename,
-- gra code action, grr references, gri implementation, gO symbols,
-- [d / ]d next/prev diagnostic, Ctrl-W d diagnostic popup, Ctrl-S signature.
vim.diagnostic.config({
  virtual_text = { spacing = 2, prefix = "●" },
  severity_sort = true,
  float = { source = true },
})
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    local map = function(lhs, fn, desc)
      vim.keymap.set("n", lhs, fn, { buffer = ev.buf, desc = desc })
    end
    map("gd", vim.lsp.buf.definition, "Go to definition")
    map("gD", vim.lsp.buf.declaration, "Go to declaration")
    map("<leader>cf", function() vim.lsp.buf.format({ async = true }) end, "Format file")
  end,
})

-- Python environment for basedpyright (lua/python-env.lua): auto-detected,
-- Space p e / :PythonEnv to pick a venv or conda env for the project.
vim.api.nvim_create_user_command("PythonEnv", function() require("python-env").pick() end,
                                 { desc = "Pick the Python environment" })
vim.keymap.set("n", "<leader>pe", "<cmd>PythonEnv<cr>", { desc = "Choose Python environment" })

-- Ctrl+V pastes the system clipboard like in other apps (p / P already do,
-- via clipboard=unnamedplus; Ctrl+Shift+V is Ghostty's own paste). Vim's
-- old Ctrl+V jobs live on Ctrl+Q: visual-block in normal mode, insert a
-- literal key in insert / command-line mode.
vim.keymap.set("n", "<C-v>", '"+P', { desc = "Paste from clipboard" })
vim.keymap.set("i", "<C-v>", "<C-r><C-o>+", { desc = "Paste from clipboard" })
vim.keymap.set("c", "<C-v>", "<C-r>+", { desc = "Paste from clipboard" })

-- Ctrl+` flips between the code and a terminal (VS Code's terminal key; like
-- Ctrl+^, but always lands on the right kind of buffer). From code: the last
-- terminal used — its window if one is open (e.g. after :split | terminal),
-- else shown in this window — or a new :terminal if there's none; ready to
-- type. From the terminal: back to the last file.
-- Ctrl+` only reaches nvim as its own key because nvim turns on Ghostty's
-- "CSI u" key encoding (:help tui-csiu); in plain encoding it's Ctrl+Space.
-- Keys ruled out: Ctrl+T (zsh's yazi picker in the terminal), Shift+Tab
-- (zsh / Claude Code use it), Ctrl+Tab (Ghostty's next tab), Shift+T (Vim's
-- T motion, and a capital T in the terminal), Alt+T (Claude Code thinking).
--
-- Shift+Esc leaves terminal typing mode (same as Ctrl+\ Ctrl+N), so : works.
-- Plain Esc stays with the program in the terminal: zsh, Claude Code
-- (interrupt), fzf / yazi / less (close) all need it. Also needs CSI u.
local last = {}   -- most recent buffer of each kind: last.code, last.term
local function is_term(b) return vim.bo[b].buftype == "terminal" end
vim.api.nvim_create_autocmd("BufEnter", {
  callback = function(ev)   -- scheduled: a new terminal's BufEnter comes before it's a terminal
    vim.schedule(function()
      local b = ev.buf
      if not vim.api.nvim_buf_is_valid(b) then return end
      if is_term(b) then last.term = b
      elseif vim.bo[b].buflisted and vim.bo[b].buftype == "" then last.code = b end
    end)
  end,
})
function _G.rice_term_toggle()
  local function go(buf)   -- jump to a window showing buf, else show it here
    local win = vim.fn.bufwinid(buf)
    if win ~= -1 then vim.api.nvim_set_current_win(win) else vim.api.nvim_set_current_buf(buf) end
  end
  local valid = function(b) return b and vim.api.nvim_buf_is_valid(b) end
  if is_term(0) then
    if valid(last.code) then go(last.code) else vim.notify("No file to go back to") end
  else
    if valid(last.term) then go(last.term) else vim.cmd.terminal() end
    vim.cmd.startinsert()
  end
end
vim.keymap.set("n", "<C-`>", _G.rice_term_toggle, { desc = "Switch between code and terminal" })
vim.keymap.set("t", "<C-`>", [[<C-\><C-n><Cmd>lua rice_term_toggle()<CR>]],
               { desc = "Switch between code and terminal" })
vim.keymap.set("t", "<S-Esc>", [[<C-\><C-n>]], { desc = "Stop typing in the terminal" })

-- set-accent.sh rewrites theme/accent, set-theme.sh replaces palette.json;
-- watch the directory (palette.json is mv'd into place, a file watch would
-- lose it) and recolour every open nvim. Debounced: a theme switch touches
-- both files a moment apart.
local theme_dir = vim.fn.expand("~/.config/hypr/theme")
if vim.uv.fs_stat(theme_dir) then
  local watcher, timer = vim.uv.new_fs_event(), vim.uv.new_timer()
  watcher:start(theme_dir, {}, function(_, file)
    if file ~= "accent" and file ~= "palette.json" then return end
    timer:stop()
    timer:start(150, 0, vim.schedule_wrap(function()
      if vim.g.colors_name == "rice" then vim.cmd.colorscheme("rice") end
    end))
  end)
end

-- Keymaps moved in the desktop's Settings › Keybindings › Neovim
-- (keymap-overrides.json; lua/keymap-overrides.lua).
require("keymap-overrides").setup()

-- ─── Statusline: accent mode pill · file · position ────────────────────────
local modes = {
  n = "NORMAL", i = "INSERT", v = "VISUAL", V = "V-LINE", ["\22"] = "V-BLOCK",
  c = "COMMAND", R = "REPLACE", s = "SELECT", S = "S-LINE", t = "TERMINAL",
}
function _G.rice_statusline()
  local m = modes[vim.api.nvim_get_mode().mode:sub(1, 1)] or "NORMAL"
  if vim.g.statusline_winid ~= vim.api.nvim_get_current_win() then
    return " %f %m%=%l:%c "
  end
  local pyenv = vim.bo.filetype == "python" and require("python-env").label(0) or ""
  return table.concat({
    "%#RiceMode# ", m, " %#RiceModeEdge#",
    "%#RiceFile# %f", "%#RiceMod#%( %m%)", "%#StatusLine#",
    "%=", pyenv ~= "" and ("󰌠 " .. pyenv .. "  ") or "",
    "%( %{&filetype} %)  %l:%c  %p%% ",
  })
end
o.statusline = "%!v:lua.rice_statusline()"
