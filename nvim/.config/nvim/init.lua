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
vim.keymap.set("n", "<leader>pe", "<cmd>PythonEnv<cr>", { desc = "Python environment" })

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
