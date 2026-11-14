---@module 'terminal.core.context'
--- What a terminal is *for*: the project root it belongs to and the name it gets.
---
--- The editor is read through an injected `deps` table so the decisions are testable without
--- one; `from_editor()` builds the real thing.

local M = {}

--- The canonical spelling of a directory, so that one project has ONE registry key: the real path
--- (8.3 short names and symlinks resolved), forward slashes, an upper-case drive letter.
--- `getcwd()` keeps the spelling it was changed with while a file buffer's name arrives in the long
--- form; without this a terminal toggled from a terminal buffer would not find itself again.
--- Only the KEY is canonical: the shell starts in the directory the user is in, spelled as the
--- user spelled it (a junction or symlink stays what `:pwd` shows).
---@param path string
---@return string
local function canonical(path)
  local key = require("lib.nvim.fs.normkey")(path)
  return key ~= "" and key or path
end

--- The deps backed by the running editor.
---@return Terminal.ContextDeps
function M.from_editor()
  return {
    cwd = function()
      return vim.fn.getcwd()
    end,
    bufname = function()
      return vim.api.nvim_buf_get_name(0)
    end,
    root = function(path)
      local start = path ~= "" and path or vim.fn.getcwd()
      return vim.fs.root(start, { ".git" })
    end,
    key = canonical,
    isdir = function(path)
      return vim.fn.isdirectory(path) == 1
    end,
  }
end

---@internal
---@param p string
---@param literal? boolean `true`: a `$NAME` in the path is a name on disk, not a variable to expand
---@return string
local function normalize(p, literal)
  local out = vim.fs.normalize(p, { expand_env = not literal }):gsub("/+$", "")
  -- A filesystem root loses its only slash above: "/" -> "", "C:/" -> "C:" (a drive-relative path).
  if out == "" then
    return "/"
  elseif out:find("^%a:$") then
    return out .. "/"
  end
  return out
end

--- Directory a new terminal starts in, and the root that identifies its project.
---
--- `mode`: "project" = the git root of the current buffer (else the cwd), "buffer" = the
--- directory of the current buffer (else the cwd), "cwd" = the cwd. The first result is where
--- the shell starts (spelled as the user is in it); the second is the project's registry key
--- (canonical, the same for every spelling of the directory).
---@param mode Terminal.CwdMode
---@param deps Terminal.ContextDeps
---@return string cwd
---@return string root
function M.resolve(mode, deps)
  local cwd = normalize(deps.cwd())
  local bufname = deps.bufname()
  local buf_dir = nil
  if bufname ~= "" and not bufname:find("^%a[%w+.-]*://") then
    buf_dir = normalize(vim.fs.dirname(bufname))
  end

  local project = deps.root(buf_dir or cwd)
  local top = normalize(project or cwd)
  local root = deps.key and normalize(deps.key(top)) or top

  if mode == "cwd" then
    return cwd, root
  elseif mode == "buffer" then
    return buf_dir or cwd, root
  end
  return top, root
end

--- A directory named by the caller (`Terminal.Target.dir`): where the terminal starts, the project
--- it belongs to, and the name it gets when the caller gave none.
---
--- The project is the git root above the directory; without one, the project the editor is in when
--- the directory lies in it, else the directory itself. So a terminal opened for a folder is
--- listed with the other terminals of that project. Its name is the path of
--- the folder below that root (`docs/api`), which is what tells two folders of one project apart;
--- the root itself has no such name (nil: the caller's default applies, so the directory of the
--- project is the project's own terminal). The name is taken from the canonical spelling, so every
--- spelling of one folder (8.3, a symlink, the case of a drive letter) is one terminal.
---
--- A relative directory is read from the cwd; `~` is the home directory; a `$` is a character of
--- the name. What is not a directory on disk is refused, never replaced by the cwd.
---@param dir any
---@param deps Terminal.ContextDeps
---@return string|nil cwd # nil: `root_or_err` is the reason
---@return string root_or_err
---@return string|nil folder # Name for the terminal; nil: the directory is the project root
function M.resolve_dir(dir, deps)
  if type(dir) ~= "string" or dir == "" then
    return nil, "target.dir must be a non-empty string"
  end
  local path = normalize(dir, true)
  if not (path:find("^/") or path:find("^%a:/")) then
    path = normalize(vim.fs.joinpath(normalize(deps.cwd()), path), true)
  end
  local isdir = deps.isdir or function(p)
    return vim.fn.isdirectory(p) == 1
  end
  if not isdir(path) then
    return nil, ("target.dir is not a directory: %s"):format(dir)
  end

  local key = deps.key or function(p)
    return p
  end
  local own = normalize(key(path), true)
  ---@param root string
  ---@return string|nil rest # The path of `own` below `root`; nil: not below it
  local function below(root)
    local prefix = root:sub(-1) == "/" and root or (root .. "/")
    return own:sub(1, #prefix) == prefix and own:sub(#prefix + 1) or nil
  end

  local root
  local top = deps.root(path)
  if top then
    root = normalize(key(normalize(top, true)), true)
  else
    -- No project above the directory. A folder of the project the editor is in belongs to that
    -- project (a tree without git still has one list of terminals); any other is its own.
    local _, current = M.resolve("project", deps)
    root = (own == current or below(current)) and current or own
  end

  local folder = nil
  if own ~= root then
    local rest = below(root)
    if rest then
      folder = rest
    else
      -- the root is not above the directory in its canonical spelling (a link out of the
      -- project): the last component still tells the folder from the project's own terminal
      folder = vim.fs.basename(own)
    end
  end
  return path, root, folder
end

--- The name a terminal gets when the caller gave none: the configured default for no count,
--- the count itself otherwise (`3<A-h>` -> terminal "3"). "No count" is `nil` or `0` (what
--- `vim.v.count` is without one); anything else that is not a number from 1 up is a mistake of
--- the caller and is reported, not read as "no count". A fraction is cut off (`3.9` -> "3").
---@param count number|nil
---@param default_name string
---@return string|nil name
---@return string|nil err
function M.name_for_count(count, default_name)
  if count == nil or count == 0 then
    return default_name, nil
  end
  if type(count) == "number" and count >= 1 and count < math.huge then
    return tostring(math.floor(count)), nil
  end
  return nil,
    ("count must be a number from 1 up (0 or nil: the default terminal), got %s"):format(
      tostring(count)
    )
end

return M
