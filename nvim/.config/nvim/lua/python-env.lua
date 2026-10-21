-- Which Python environment basedpyright analyses against — that decides
-- whether `import numpy` resolves, which completions show, etc.
--
-- Picked automatically when the server starts, first match wins:
--   1. a choice made with :PythonEnv (Space p e) for this project or a parent
--   2. an activated env: $VIRTUAL_ENV, or $CONDA_PREFIX (nvim started from a
--      shell after `source …/bin/activate` / `conda activate`)
--   3. a venv next to the code: any folder holding a pyvenv.cfg, in the file's
--      folder or a parent of it (stops below ~, so ~/dl_lab isn't used for
--      everything). Catches .venv, venv, and named ones like cv/ or slt/.
--   4. otherwise basedpyright's default: the `python` on PATH
--
-- :PythonEnv lists those venvs, the conda envs (miniconda3, miniforge3, …) and
-- the system python; the choice is remembered per project in
-- ~/.local/share/nvim/python-envs.json and applied to the running server.

local M = {}

local HOME = vim.uv.os_homedir()
local STORE = vim.fn.stdpath("data") .. "/python-envs.json"
local MARKERS = { "pyrightconfig.json", "pyproject.toml", "setup.py", "setup.cfg",
                  "requirements.txt", "Pipfile", ".git" }
local CONDA_ROOTS = { "miniconda3", "miniforge3", "anaconda3", "mambaforge", ".conda" }

local function scandir(dir)   -- vim.fs.dir, but quiet on unreadable folders
  local ok, it = pcall(vim.fs.dir, dir)
  return ok and it or function() end
end

local function python_in(env)
  local p = env .. "/bin/python"
  return vim.fn.executable(p) == 1 and p or nil
end

local function load()
  local f = io.open(STORE)
  if not f then return {} end
  local ok, t = pcall(vim.json.decode, f:read("a"))
  f:close()
  return ok and type(t) == "table" and t or {}
end

local function save(t)
  local f = io.open(STORE, "w")
  if f then f:write(vim.json.encode(t)); f:close() end
end

-- every venv in `start` or a parent of it (nearest first), never at ~ or above
local function venvs_near(start)
  local found, dir = {}, start
  while dir and dir ~= HOME and dir ~= "/" do
    local here = {}
    for name, kind in scandir(dir) do
      local env = dir .. "/" .. name
      if (kind == "directory" or kind == "link") and vim.uv.fs_stat(env .. "/pyvenv.cfg")
          and python_in(env) then
        here[#here + 1] = env
      end
    end
    -- .venv / venv before oddly named ones in the same folder
    table.sort(here, function(a, b)
      local pa = vim.fs.basename(a):match("^%.?venv$") and 0 or 1
      local pb = vim.fs.basename(b):match("^%.?venv$") and 0 or 1
      return pa ~= pb and pa < pb or (pa == pb and a < b)
    end)
    vim.list_extend(found, here)
    dir = vim.fs.dirname(dir)
  end
  return found
end

local function conda_envs()
  local out = {}
  for _, r in ipairs(CONDA_ROOTS) do
    local root = HOME .. "/" .. r
    if python_in(root) then out[#out + 1] = root end
    if vim.uv.fs_stat(root .. "/envs") then
      for name, kind in scandir(root .. "/envs") do
        local env = root .. "/envs/" .. name
        if (kind == "directory" or kind == "link") and python_in(env) then out[#out + 1] = env end
      end
    end
  end
  return out
end

-- The project a python file belongs to. Without a marker (.git,
-- pyproject.toml, …) a bare course folder would have NO root, and Neovim then
-- shares one server across all such files — so they couldn't use different
-- envs. Fall back to the folder holding the nearest venv, else the file's own.
function M.root(bufnr, on_dir)
  local file = vim.api.nvim_buf_get_name(bufnr)
  local root = vim.fs.root(bufnr, MARKERS)
  if root and root ~= HOME then return on_dir(root) end
  local dir = vim.fs.dirname(file)
  local venv = venvs_near(dir)[1]
  on_dir(venv and vim.fs.dirname(venv) or dir)
end

-- python path + why it was chosen, for a project root
function M.resolve(root)
  local saved, dir = load(), root
  while dir do
    if saved[dir] and vim.fn.executable(saved[dir]) == 1 then return saved[dir], "chosen" end
    local up = vim.fs.dirname(dir)
    dir = up ~= dir and up or nil
  end
  for _, var in ipairs({ "VIRTUAL_ENV", "CONDA_PREFIX" }) do
    local env = vim.env[var]
    if env and env ~= "" and python_in(env) then return python_in(env), "activated" end
  end
  local venv = venvs_near(root)[1]
  if venv then return python_in(venv), "project" end
end

-- basedpyright's before_init: set python.pythonPath before it starts
function M.before_init(_, config)
  local path = M.resolve(config.root_dir)
  if path then
    -- in place: the client already holds a reference to this settings table
    config.settings = config.settings or {}
    config.settings.python = config.settings.python or {}
    config.settings.python.pythonPath = path
  end
end

-- "cv", "aiops", "system" … for the statusline
local function env_name(path)
  if not path then return "system" end
  local env = path:gsub("/bin/python[%d.]*$", "")
  if env == "/usr" then return "system" end
  return vim.fs.basename(env)
end

function M.label(bufnr)
  local c = vim.lsp.get_clients({ bufnr = bufnr, name = "basedpyright" })[1]
  if not c then return "" end
  return env_name(vim.tbl_get(c.settings or {}, "python", "pythonPath"))
end

local function apply(client, path)
  client.settings = vim.tbl_deep_extend("force", client.settings or {}, { python = {} })
  client.settings.python.pythonPath = path   -- nil = basedpyright's default
  client:notify("workspace/didChangeConfiguration", { settings = nil })
  vim.cmd.redrawstatus()
end

function M.pick()
  local bufnr = vim.api.nvim_get_current_buf()
  local client = vim.lsp.get_clients({ bufnr = bufnr, name = "basedpyright" })[1]
  if not client then
    return vim.notify("No Python language server on this buffer — open a .py file first",
                      vim.log.levels.WARN)
  end
  local root = client.root_dir or vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr))
  local current = vim.tbl_get(client.settings or {}, "python", "pythonPath")

  local items, seen = {}, {}
  local function add(kind, env, path)
    path = path or python_in(env)
    if not path or seen[path] then return end
    seen[path] = true
    items[#items + 1] = { kind = kind, env = env, path = path }
  end
  local saved = load()
  items[1] = { kind = "auto", path = false }
  for _, env in ipairs(venvs_near(root)) do add("venv", env) end
  for _, env in ipairs(conda_envs()) do add("conda", env) end
  add("system", "/usr", vim.fn.exepath("python3"))

  vim.ui.select(items, {
    prompt = "Python env for " .. vim.fn.fnamemodify(root, ":~") .. ": ",
    format_item = function(it)
      if it.kind == "auto" then
        return ("%s automatic (activated env / nearest venv)"):format(saved[root] and " " or "●")
      end
      local mark = it.path == current and "●" or " "
      return ("%s %-7s %-14s %s"):format(mark, it.kind, env_name(it.path),
                                          vim.fn.fnamemodify(it.env, ":~"))
    end,
  }, function(choice)
    if not choice then return end
    local store = load()
    local path
    if choice.kind == "auto" then
      store[root] = nil
      path = M.resolve(root)
    else
      store[root] = choice.path
      path = choice.path
    end
    save(store)
    for _, c in ipairs(vim.lsp.get_clients({ name = "basedpyright" })) do
      if c.root_dir == root then apply(c, path) end
    end
    vim.notify(("Python env: %s (%s)"):format(env_name(path), path or "basedpyright default"))
  end)
end

return M
