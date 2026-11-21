---@module 'terminal.status.nested'
--- Is this Neovim running inside the terminal of another, still running Neovim? Such a Neovim stays
--- out of the multiplexer's status: the outer one owns the pane. The question is answered from the
--- environment variable `$NVIM` (the outer server's address), the outer server itself (its pid) and
--- the process tree. Used by the tmux exporter (`available`), kept apart from it because it is a
--- process-ancestry detector, not a tmux concern.
---@see terminal.status.exporters.tmux

local M = {}

--- Whether the Neovim at `address` (the value of `$NVIM`) is still running -- only that; whether
--- this Neovim is nested in it is `M.nested`. A tmux server that was started from a Neovim
--- terminal hands that variable to every pane for good, long after that Neovim exited: a dead
--- address is no outer Neovim.
---@type fun(address: string): boolean
M.alive = function(address)
  -- `--listen host:port` gives a TCP address (no path separator, ends in :<port>); everything
  -- else is a unix socket path or a Windows named pipe.
  local mode = (not address:find("[/\\]") and address:find(":%d+$")) and "tcp" or "pipe"
  local ok, channel = pcall(vim.fn.sockconnect, mode, address, { rpc = true })
  if not ok or type(channel) ~= "number" or channel <= 0 then
    return false
  end
  pcall(vim.fn.chanclose, channel)
  return true
end

--- The parent process id out of one line of `/proc/<pid>/stat`: `<pid> (<comm>) <state> <ppid> ...`.
--- The kernel ends `comm` at the LAST `)`, and `comm` can hold spaces and parentheses itself
--- (`x) R 1 (y`), so the pattern is greedy -- a balanced match would stop at the first one and read
--- a number out of the name.
---@param line string|nil
---@return integer|nil
function M.parse_stat(line)
  local ppid = line and line:match("^%d+ %(.*%) %S (%d+)")
  return ppid and tonumber(ppid) or nil
end

--- The parent of `pid` out of `/proc` (Linux): read at once, no process. nil without /proc.
---@internal
---@param pid integer
---@return integer|nil
local function proc_parent(pid)
  local f = io.open(("/proc/%d/stat"):format(pid), "r")
  if not f then
    return nil
  end
  local line = f:read("*l")
  f:close()
  return M.parse_stat(line)
end

--- The `ps` that tells the parent of `pid`, or nil where none can: on Windows a `ps` (Git Bash)
--- numbers processes in its own namespace.
---@internal
---@param pid integer
---@return string[]|nil argv
local function ps_argv(pid)
  if require("lib.nvim.cross.platform.is_windows")() or vim.fn.executable("ps") ~= 1 then
    return nil
  end
  return { "ps", "-o", "ppid=", "-p", tostring(pid) }
end

--- One second for `ps`: it answers at once, the limit only bounds a hang.
local PS_TIMEOUT_MS = 1000

---@internal
---@param res Terminal.ExecResult
---@return integer|nil
local function ps_parent(res)
  return res.code == 0 and tonumber(vim.trim(res.stdout)) or nil
end

--- The parent process id of `pid`; nil when it cannot be read (no /proc and no `ps`). Blocks for
--- the `ps` (macOS, the BSDs); `parent_of_async` is the form that does not.
---@type fun(pid: integer): integer|nil
M.parent_of = function(pid)
  local parent = proc_parent(pid)
  if parent then
    return parent
  end
  local argv = ps_argv(pid)
  if argv then
    return ps_parent(require("terminal.core.exec").run(argv, { timeout = PS_TIMEOUT_MS }))
  end
  return nil
end

--- `parent_of` without waiting: `done(parent)` on the main loop, also when /proc answers at once.
---@type fun(pid: integer, done: fun(parent: integer|nil))
M.parent_of_async = function(pid, done)
  local parent = proc_parent(pid)
  local argv = not parent and ps_argv(pid) or nil
  if not argv then
    vim.schedule(function()
      done(parent)
    end)
    return
  end
  require("terminal.core.exec").spawn(argv, { timeout = PS_TIMEOUT_MS }, function(res)
    done(ps_parent(res))
  end)
end

--- Whether the process `pid` is an ancestor of this Neovim: `done(true / false)`, `done(nil)` when
--- the chain cannot be followed. One walk for both forms: `parent(p, k)` hands the parent of `p`
--- to `k`, at once (blocking form) or later (asynchronous form).
---@internal
---@param pid integer
---@param parent fun(p: integer, k: fun(parent: integer|nil))
---@param done fun(ancestor: boolean|nil)
local function walk_ancestors(pid, parent, done)
  -- 64 levels: deeper than any real process chain, it only ends a loop in a broken parent table.
  local levels = 64
  local function step(current)
    parent(current, function(p)
      if p == nil then
        return done(nil)
      end
      if p == pid then
        return done(true)
      end
      levels = levels - 1
      if p <= 1 or levels <= 0 then
        return done(false)
      end
      step(p)
    end)
  end
  step(vim.uv.os_getpid())
end

--- How long the outer server may take to tell its pid: it bounds how long the status of a nested
--- Neovim stays unknown, a server that stays silent leaves the nesting unknown (nil).
local SERVER_TIMEOUT_MS = 1500

--- The client that asks the server at `address` for its pid.
---@internal
---@param address string
---@return string[] argv
local function server_pid_argv(address)
  return {
    vim.v.progpath,
    -- `--headless`: without it a `--remote-expr` client prints nothing on Windows (and waits
    -- 1 s); `-u NONE -i NONE` keeps the client from loading a config and shada.
    "--headless",
    "-u",
    "NONE",
    "-i",
    "NONE",
    "--server",
    address,
    "--remote-expr",
    "getpid()",
  }
end

---@internal
---@param res Terminal.ExecResult
---@return integer|nil
local function server_pid_of(res)
  if res.code ~= 0 then
    return nil
  end
  return tonumber(vim.trim(res.stdout))
end

--- The process id of the Neovim server at `address`, asked of the server itself: nothing is
--- guessed from the address (a default servername is `<appname>.<pid>.<n>`, but a custom `--listen`
--- name or a TCP address can look like it or look like anything). Done by a child `nvim --server
--- <address> --remote-expr getpid()` with a timeout, never by an RPC call in this process: a
--- server that is busy (the outer Neovim sits in a blocking `:!`) must not freeze this one.
--- nil when it does not answer within 1.5 s. Blocks; `server_pid_async` is the form that does not.
---@type fun(address: string): integer|nil
M.server_pid = function(address)
  return server_pid_of(
    require("terminal.core.exec").run(server_pid_argv(address), { timeout = SERVER_TIMEOUT_MS })
  )
end

--- `server_pid` without waiting: `done(pid)` on the main loop.
---@type fun(address: string, done: fun(pid: integer|nil))
M.server_pid_async = function(address, done)
  require("terminal.core.exec").spawn(
    server_pid_argv(address),
    { timeout = SERVER_TIMEOUT_MS },
    function(res)
      done(server_pid_of(res))
    end
  )
end

--- Whether this Neovim runs inside the terminal of the (running) Neovim at `address`: the one
--- `$NVIM` names. A Neovim in a pane of a tmux server that merely *was started* from that
--- terminal has the same `$NVIM` but is not a descendant of it -- it owns its pane. So a running
--- outer Neovim counts when it is an ancestor of this process (its pid asked of the server, the
--- process tree read from /proc or `ps`). When either cannot be found out -- the server does not
--- answer in time, no readable process tree (Windows) -- the answer is `nil`, unknown: the caller
--- decides (the tmux exporter publishes anyway and warns once; fail-closed would leave the pane
--- without a status and without a word).
---
--- Blocks for the server's answer (up to 1.5 s) and every `ps`; the tmux exporter asks
--- `nested_async` instead.
---@param address string
---@return boolean|nil nested  true / false when known, nil when it cannot be found out
function M.nested(address)
  if not M.alive(address) then
    return false
  end
  local pid = M.server_pid(address)
  if pid == nil then
    return nil
  end
  local answer
  walk_ancestors(pid, function(p, k)
    k(M.parent_of(p))
  end, function(ancestor)
    answer = ancestor
  end)
  return answer
end

--- `nested` without waiting for any process: `done(nested)` on the main loop, exactly once. Only
--- the connect to `address` (`alive`, no process) happens before it returns.
---@param address string
---@param done fun(nested: boolean|nil)
---@return nil
function M.nested_async(address, done)
  local answered = false
  local function answer(nested)
    if not answered then
      answered = true
      done(nested)
    end
  end
  if not M.alive(address) then
    vim.schedule(function()
      answer(false)
    end)
    return
  end
  M.server_pid_async(address, function(pid)
    if pid == nil then
      return answer(nil)
    end
    walk_ancestors(pid, M.parent_of_async, answer)
  end)
end

return M
