-- Keymaps moved to other keys in the desktop's Settings › Keybindings ›
-- Neovim (~/.config/hypr/settings-nvim.py writes keymap-overrides.json):
--
--   { "n": { "<leader>ff": "<leader>fx" }, … }      mode → { old lhs: new lhs }
--
-- Each one is MOVED: the mapping at the old keys (whatever defined it —
-- this config, a plugin, Neovim's defaults) is re-created on the new keys
-- with the same rhs/callback/options, and the old keys are freed. Applied
-- at VimEnter, again after a lazy-loaded plugin defines its keys (User
-- LazyLoad, a moment later so lazy's own replay of the pressed keys still
-- finds them), and per buffer on LspAttach (gd, gD, <leader>cf live there).
--
-- "_custom": [ { "mode": "n", "lhs": "<leader>w", "rhs": ":w<CR>", "desc": … } ]
-- are mappings of your own (Settings › Keybindings › Neovim › Add) — or an
-- existing mapping edited there ("edited": true, same keys, new action /
-- description), or one deleted there ("deleted": true: its keys are freed).
-- Set AFTER the moves (so an edit of a moved key wins), and
-- again after a lazy-loaded plugin defines its keys.
local M = {}

local file = vim.fn.stdpath("config") .. "/keymap-overrides.json"

function M.read()
  local f = io.open(file, "r")
  if not f then return {} end
  local ok, t = pcall(vim.json.decode, f:read("*a"))
  f:close()
  return ok and type(t) == "table" and t or {}
end

local function move(mode, from, to, buf)
  local d = vim.fn.maparg(from, mode, false, true)
  if type(d) ~= "table" or not d.lhs then return end
  if buf and d.buffer ~= 1 then return end      -- LspAttach pass: buffer maps only
  if not buf and d.buffer == 1 then return end
  local rhs = d.callback or d.rhs
  if not rhs then return end
  pcall(vim.keymap.del, mode, from, buf and { buffer = buf } or {})
  vim.keymap.set(mode, to, rhs, {
    buffer = buf, desc = d.desc, expr = d.expr == 1, silent = d.silent == 1,
    nowait = d.nowait == 1, remap = d.noremap == 0, script = d.script == 1,
    replace_keycodes = d.replace_keycodes == 1 or nil,
  })
end

function M.custom()
  for _, c in ipairs(M.read()._custom or {}) do
    if type(c) == "table" and c.deleted and c.mode and c.lhs then
      pcall(vim.keymap.del, c.mode, c.lhs)       -- deleted in Settings
    elseif type(c) == "table" and c.mode and c.lhs and c.rhs and c.lhs ~= "" then
      pcall(vim.keymap.set, c.mode, c.lhs, c.rhs, { desc = c.desc ~= "" and c.desc or nil, silent = true })
    end
  end
end

function M.apply(buf)
  for mode, maps in pairs(M.read()) do if mode ~= "_custom" then
    for from, to in pairs(maps) do
      if type(to) == "string" and to ~= "" and to ~= from then move(mode, from, to, buf) end
    end
  end end
end

function M.setup()
  local g = vim.api.nvim_create_augroup("keymap-overrides", { clear = true })
  vim.api.nvim_create_autocmd("VimEnter", { group = g, callback = function() M.apply(); M.custom() end })
  vim.api.nvim_create_autocmd("User", { group = g, pattern = "LazyLoad",
    callback = function() vim.defer_fn(function() M.apply(); M.custom() end, 50) end })
  vim.api.nvim_create_autocmd("LspAttach", { group = g, callback = function(ev)
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(ev.buf) then
        vim.api.nvim_buf_call(ev.buf, function() M.apply(ev.buf) end)
      end
    end)
  end })
  if vim.v.vim_did_enter == 1 then M.apply(); M.custom() end
end

return M
