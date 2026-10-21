-- Plugins, managed by lazy.nvim (it bootstraps itself on first start).
-- :Lazy to update/inspect; versions are pinned in lazy-lock.json.
--
--   fzf-lua      file finder / grep / pickers (uses the system fzf, fd, rg)
--   blink.cmp    completion menu: LSP, paths, snippets, words in open buffers
--   mason        installs language servers into ~/.local/share/nvim/mason
--                (:Mason to browse/add more; they're auto-enabled)
--   treesitter   real parsers for syntax highlighting (:TSInstall <lang> for more)

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable",
                  "https://github.com/folke/lazy.nvim.git", lazypath })
end
vim.opt.rtp:prepend(lazypath)

local function fzf(picker, opts)
  return function() require("fzf-lua")[picker](opts) end
end

require("lazy").setup({
  spec = {
    -- ─── file finder ────────────────────────────────────────────────────────
    {
      "ibhagwan/fzf-lua",
      cmd = "FzfLua",
      keys = {
        { "<C-p>",      fzf("files"),                desc = "Find files" },
        { "<leader>ff", fzf("files"),                desc = "Find files" },
        { "<leader>fg", fzf("live_grep"),            desc = "Grep in project" },
        { "<leader>fw", fzf("grep_cword"),           desc = "Grep word under cursor" },
        { "<leader>fb", fzf("buffers"),              desc = "Open buffers" },
        { "<leader>fr", fzf("oldfiles"),             desc = "Recent files" },
        { "<leader>f/", fzf("blines"),               desc = "Lines in this file" },
        { "<leader>fs", fzf("lsp_document_symbols"), desc = "Symbols in this file" },
        { "<leader>fd", fzf("diagnostics_document"), desc = "Diagnostics in this file" },
        { "<leader>fh", fzf("helptags"),             desc = "Help" },
        { "<leader>fk", fzf("keymaps"),              desc = "Keymaps" },
        { "<leader>f.", fzf("resume"),               desc = "Reopen last picker" },
      },
      init = function()
        -- code actions & other vim.ui.select menus open in fzf too
        vim.ui.select = function(...)
          require("fzf-lua").register_ui_select()
          return vim.ui.select(...)
        end
      end,
      opts = {
        fzf_colors = true,     -- fzf takes its colours from the rice theme
        winopts = { border = "rounded", preview = { border = "rounded" } },
      },
      config = function(_, opts)
        require("fzf-lua").setup(opts)
        -- fzf-lua bug (still on main 2026-10): for Neovim's own default maps
        -- (Y, gra, grn, [d, …) the callback source is "vim/_defaults.lua" and
        -- path.keymap_to_entry appends another ".lua", so the keymaps preview
        -- warns "Unable to open file …/_defaults.lua.lua". Drop the extra one.
        -- Details, upstream fix and removal steps: UPSTREAM-BUGS.md
        local path = require("fzf-lua.path")
        local keymap_to_entry = path.keymap_to_entry
        path.keymap_to_entry = function(...)
          local e = keymap_to_entry(...)
          if e.path then
            e.path = e.path:gsub("%.lua%.lua$", ".lua")
            if e.stripped then e.stripped = e.stripped:gsub("%.lua%.lua:", ".lua:") end
          end
          return e
        end
      end,
    },

    -- ─── completion ─────────────────────────────────────────────────────────
    {
      "saghen/blink.cmp",
      version = "1.*",         -- release tag = prebuilt fuzzy-matcher binary
      dependencies = { "rafamadriz/friendly-snippets" },
      opts = {
        -- Tab / Shift-Tab pick an item, Enter accepts it. Nothing is
        -- preselected, so Enter on an open menu still just makes a new line.
        keymap = {
          preset = "enter",
          ["<Tab>"]   = { "select_next", "snippet_forward", "fallback" },
          ["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },
        },
        completion = {
          list = { selection = { preselect = false, auto_insert = true } },
          menu = { border = "rounded" },
          documentation = { auto_show = true, auto_show_delay_ms = 200,
                            window = { border = "rounded" } },
        },
        signature = { enabled = true, window = { border = "rounded" } },
        sources = { default = { "lsp", "path", "snippets", "buffer" } },
      },
    },

    -- ─── syntax highlighting ────────────────────────────────────────────────
    -- `master`, not the default `main`: main needs Neovim 0.12, Ubuntu ships
    -- 0.11. master is frozen but is the supported branch for 0.11. Parsers are
    -- compiled with the system cc into the plugin's parser/ dir, ahead of
    -- Ubuntu's bundled ones in /usr/lib/nvim, so parser and queries match.
    {
      "nvim-treesitter/nvim-treesitter",
      branch = "master",
      lazy = false,
      build = ":TSUpdate",
      main = "nvim-treesitter.configs",
      opts = {
        ensure_installed = {
          "python", "c", "cpp", "lua", "bash", "java", "go", "javascript",
          "html", "css", "json", "jsonc", "yaml", "toml", "ini", "make", "cmake",
          "markdown", "markdown_inline", "regex", "diff", "gitcommit",
          "git_rebase", "gitignore", "sql", "vim", "vimdoc", "query",
        },
        highlight = {
          enable = true,
          -- huge files (logs, CSV dumps) stay on plain regex highlighting
          disable = function(_, buf)
            local ok, st = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(buf))
            return ok and st and st.size > 512 * 1024
          end,
        },
      },
    },

    -- ─── language servers ───────────────────────────────────────────────────
    {
      "mason-org/mason-lspconfig.nvim",
      dependencies = {
        { "mason-org/mason.nvim", opts = { ui = { border = "rounded" } } },
        "neovim/nvim-lspconfig",   -- the server definitions vim.lsp.enable uses
        "saghen/blink.cmp",
      },
      config = function()
        vim.lsp.config("*", { capabilities = require("blink.cmp").get_lsp_capabilities() })
        local pyenv = require("python-env")   -- which venv/conda env (:PythonEnv)
        vim.lsp.config("basedpyright", {
          root_dir = pyenv.root,
          before_init = pyenv.before_init,
          -- "standard" = plain pyright's checks. basedpyright's default
          -- ("recommended") also flags every unused call result, missing
          -- stub, untyped value… — noise for scripts and coursework.
          -- A project's pyproject.toml / pyrightconfig.json still overrides.
          settings = { basedpyright = { analysis = { typeCheckingMode = "standard" } } },
        })
        vim.lsp.config("lua_ls", { settings = { Lua = {   -- knows about `vim.*`
          runtime = { version = "LuaJIT" },
          workspace = { checkThirdParty = false, library = { vim.env.VIMRUNTIME } },
        } } })
        -- installed on first start, then enabled for their filetypes.
        -- basedpyright installs through pip, so it needs python3-venv.
        require("mason-lspconfig").setup({
          ensure_installed = { "basedpyright", "clangd", "lua_ls" },
        })
      end,
    },
  },
  install = { colorscheme = { "rice" } },
  ui = { border = "rounded" },
  rocks = { enabled = false },
  change_detection = { notify = false },
  -- lazy trims the runtimepath to Neovim's own dirs; Debian/Ubuntu ship the
  -- bundled treesitter parsers (lua, c, vim, markdown, …) in /usr/lib/nvim,
  -- and without it opening any .lua file errors out.
  performance = { rtp = { paths = { "/usr/lib/nvim" } } },
})
