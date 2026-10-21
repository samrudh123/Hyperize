# Upstream bugs worked around in this config

Bugs in plugins that this config patches locally. Each entry says where the
workaround lives and when it can go. **Status: not reported upstream yet.**

---

## fzf-lua: keymaps preview opens `…/vim/_defaults.lua.lua`

| | |
|---|---|
| Plugin | [ibhagwan/fzf-lua](https://github.com/ibhagwan/fzf-lua) |
| Seen on | commit `348df16` (main, 2026-10-19); still present on `origin/main` 2026-10-20 |
| Introduced | older than `de0ec78` "fix(actions): keymap_edit don't work" (2026-09-15), which touched the function but kept the bad line; exact commit not traced |
| Neovim | 0.11.6 (Ubuntu 26.04 `neovim` package) |
| Workaround | `lua/plugins.lua`, fzf-lua `config` — wraps `require("fzf-lua.path").keymap_to_entry` |
| Reported | **no** (held off on purpose) |

### Symptom

`:FzfLua keymaps` (`Space f k`), then move the cursor through the list. Whenever
it lands on one of Neovim's own default maps (`Y`, `&`, `grn`, `gra`, `grr`,
`gri`, `gO`, `[d`, `]d`, `<C-S>` …) the previewer warns:

```
[Fzf-lua] Unable to open file '/usr/share/nvim/runtime/lua/vim/_defaults.lua.lua', error: ENOENT: no such file or directory: /usr/share/nvim/runtime/lua/vim/_defaults.lua.lua
```

and the preview is empty. Maps from the user config or plugins preview fine,
which is why it looks intermittent.

### Reproduce

```sh
nvim --clean -u NONE \
  --cmd 'set rtp+=~/.local/share/nvim/lazy/fzf-lua' \
  -c 'lua require("fzf-lua").setup({})' \
  -c 'FzfLua keymaps'
# type "_defaults" or scroll to any default map such as `Y`
```

Scripted (what was used to find it): run nvim in a private tmux server
(`tmux -L nvtest -f /dev/null new -d -x 200 -y 50 nvim`), `send-keys ' fk'`,
then 60× `Down` and 60× `Up`, and read `:messages`.

### Cause

`lua/fzf-lua/path.lua`, `M.keymap_to_entry`:

```lua
local source = info.source:gsub("^@", "")
-- https://github.com/neovim/neovim/blob/64d55b74…/src/nvim/lua/executor.c#L671-L680
if source:match("vim/") and package.preload[source:gsub("%.lua$", ""):gsub("/", ".")] then
  source = vim.env.VIMRUNTIME .. "/lua/" .. source .. ".lua"
end
```

The condition already allows for a source that ends in `.lua` (it strips it
before the `package.preload` lookup), but the path it builds appends `.lua`
again. On this Neovim the callback's `debug.getinfo().source` **is**
`@vim/_defaults.lua`:

```sh
nvim --clean --headless -c 'lua for _,k in ipairs(vim.api.nvim_get_keymap("n")) do
  if k.callback then local s=debug.getinfo(k.callback,"S").source
  if s:match("defaults") then print(k.lhs, s) break end end end' -c qa
# -> [  @vim/_defaults.lua
```

so the result is `$VIMRUNTIME/lua/vim/_defaults.lua.lua`. Both `path` and
`stripped` carry it, so the "edit keymap" action (`keymap_edit`) is affected too.

### Suggested upstream fix

```diff
-      if source:match("vim/") and package.preload[source:gsub("%.lua$", ""):gsub("/", ".")] then
-        source = vim.env.VIMRUNTIME .. "/lua/" .. source .. ".lua"
+      local mod = source:gsub("%.lua$", "")
+      if mod:match("vim/") and package.preload[mod:gsub("/", ".")] then
+        source = vim.env.VIMRUNTIME .. "/lua/" .. mod .. ".lua"
       end
```

### Workaround here

`lua/plugins.lua` replaces `path.keymap_to_entry` with a wrapper that rewrites
a trailing `.lua.lua` to `.lua` in `path` and `stripped`. Verified with the
tmux run above: no warnings, and the preview shows the real `_defaults.lua`
source.

**Remove it** once fzf-lua is fixed: after `:Lazy update`, check
`~/.local/share/nvim/lazy/fzf-lua/lua/fzf-lua/path.lua` no longer appends
`.. ".lua"` to an already-`.lua` source, delete the wrapper (keep the plain
`require("fzf-lua").setup(opts)`), and repeat the reproduction.

### Draft issue (for when it gets reported)

> **Title:** keymaps previewer: `vim/_defaults.lua.lua` ENOENT for Neovim's default mappings
>
> On Neovim 0.11.6 `debug.getinfo(cb).source` for the built-in default maps is
> `@vim/_defaults.lua`. `path.keymap_to_entry` strips `.lua` for the
> `package.preload` check but then appends `.lua` to the unstripped source, so
> the previewer (and `keymap_edit`) try to open
> `$VIMRUNTIME/lua/vim/_defaults.lua.lua` and warn
> `Unable to open file … ENOENT`. Repro: `:FzfLua keymaps`, move onto `Y` or
> `grn`. Fix: build the path from the stripped module name (diff above).
