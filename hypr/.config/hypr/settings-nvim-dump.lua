-- Dumps Neovim's keymaps as JSON for Settings › Keybindings › Neovim.
-- Run by settings-nvim.py:  nvim --headless -c "luafile THIS" (output path in
-- $SETTINGS_NVIM_OUT). Waits for VimEnter (lazy.nvim has set up its key stubs
-- by then), fakes an LspAttach on a scratch buffer so the buffer-local LSP
-- maps from init.lua show up too, then writes and quits.
local out = os.getenv("SETTINGS_NVIM_OUT") or "/dev/stdout"

local function source_of(d)
  if d.callback then
    local info = debug.getinfo(d.callback, "S")
    return info and info.source or ""
  end
  if d.sid and d.sid > 0 then
    local s = vim.fn.getscriptinfo({ sid = d.sid })
    return s[1] and s[1].name or ""
  end
  return ""
end

local function group_of(src, lhs, desc)
  local cfg = vim.fn.stdpath("config")
  if src:find("lazy/core/handler", 1, true) then return "Plugins (load on first use)" end
  local plug = src:match("/lazy/([^/]+)/")
  if plug then return "Plugin: " .. plug end
  if src:find(cfg, 1, true) or src:find("nvim/lua/", 1, true) then return "Your config" end
  if src:find("_defaults", 1, true) or src:find("/runtime/", 1, true) or src:find("/usr/share/nvim", 1, true) then
    return "Neovim defaults"
  end
  return src == "" and "Neovim defaults" or "Your config"
end

local function dump()
  -- buffer-local LSP maps (init.lua's LspAttach) on a scratch buffer
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_set_current_buf(buf)
  pcall(vim.api.nvim_exec_autocmds, "LspAttach", { buffer = buf, data = { client_id = 0 } })
  vim.wait(120, function() return false end)
  local leader = vim.g.mapleader or "\\"
  local res, seen = {}, {}
  local function add(d, buffer)
    if d.lhs:find("<Plug>", 1, true) or d.lhs:find("^<SNR>") then return end
    local key = d.mode .. "\0" .. d.lhs .. (buffer and "b" or "")
    if seen[key] then return end
    seen[key] = true
    local lhs = d.lhs
    if leader == " " then lhs = lhs:gsub("^ ", "<leader>"):gsub("^<Space>", "<leader>") end
    local src = source_of(d)
    table.insert(res, {
      mode = d.mode, lhs = lhs, rawLhs = d.lhs, desc = d.desc or "",
      rhs = d.rhs or (d.callback and "<Lua function>" or ""),
      buffer = buffer or false,
      group = buffer and "LSP (when a language server attaches)" or group_of(src, d.lhs, d.desc),
    })
  end
  for _, m in ipairs({ "n", "i", "x", "s", "o", "t", "c" }) do
    for _, d in ipairs(vim.api.nvim_get_keymap(m)) do d.mode = m; add(d, false) end
    for _, d in ipairs(vim.api.nvim_buf_get_keymap(buf, m)) do d.mode = m; add(d, true) end
  end
  local f = io.open(out, "w")
  f:write(vim.json.encode(res))
  f:close()
  vim.cmd("qa!")
end

if vim.v.vim_did_enter == 1 then vim.schedule(dump)
else vim.api.nvim_create_autocmd("VimEnter", { once = true, callback = function() vim.schedule(dump) end }) end
