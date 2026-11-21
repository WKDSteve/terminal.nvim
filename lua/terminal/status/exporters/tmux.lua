---@module 'terminal.status.exporters.tmux'
--- Publishes the status dataset to tmux as **pane options**, so `status-right`, `pane-border-format`
--- or `window-status-format` can show them with `#{@terminal_mode}` and friends.
---
--- One `set-option -p` per field, sent as a single tmux command line (commands joined with `;`):
---   `@terminal_mode`   Neovim mode code (`n`, `i`, `v`, `V`, `^V`, `t`, ...)
---   `@terminal_file`   file name
---   `@terminal_branch` git branch ("" when none)
---   `@terminal_diag`   `E2 W1` (errors / warnings; "" when none)
---   `@terminal_rec`    macro register being recorded ("" when none)
---   `@terminal_mod`    `+` when the buffer is modified, else ""
--- Values are sanitised by the dataset (no control characters). tmux expands `#{...}` inside a
--- format *value* only where the user's format asks for it; the values themselves are set with
--- `set-option`, never interpolated into a command string. A value that ends in `;` is escaped
--- (`core.tmux_word`): tmux would otherwise read it as the end of the command.
---
--- Whose pane it is: the options belong to `$TMUX_PANE`, so only the Neovim that *owns* the pane
--- may write them. `ready()` refuses one without an attached UI (a headless child) and, with `$NVIM`
--- set, holds the status back until a check in the background answers whether this Neovim runs
--- inside the outer one's terminal: then it drops out (`terminal.status.drop`); when that cannot be
--- found out it exports and warns once. `clear()` removes the options only when this instance
--- wrote them.
---@see terminal.backends.tmux
---@see terminal.core.status

local Env = require("terminal.core.env")
local tmux_word = require("terminal.core.tmux_word")

local M = {}

M.name = "tmux"

--- Whether this instance wrote the pane options (and so has to remove them).
local owned = false

--- Runs a tmux command and waits. The status publish itself does not block (`publish_async`); this
--- serves `publish` (synchronous, kept for callers that need the answer) and `clear` (at exit, where
--- the options must be gone before Neovim ends). The editor waits as long as tmux takes, so a hung
--- tmux gets `status.timeout_ms` (two seconds), not the backend's three.
---@type fun(argv: string[]): Terminal.ExecResult
M.run = function(argv)
  local exec = require("terminal.core.exec")
  return exec.run(argv, { timeout = exec.configured("status.timeout_ms", 2000) })
end

--- Why a tmux call failed, for the notice: its first stderr line, or the cause when it printed
--- nothing (a hung tmux ends by timeout with code 124).
---@param res Terminal.ExecResult
---@return string
local function failure(res)
  local why = require("terminal.core.errors").reason("tmux", res.stderr)
  if why == "no output" then
    why = res.code == 124 and "tmux did not answer in time"
      or ("tmux exited with code %d"):format(res.code)
  end
  return why
end

--- Whether this Neovim owns the pane although `$NVIM` is set, found out asynchronously: asking the
--- outer server for its pid starts a `nvim --server` client (100-200 ms on Windows, up to 1.5 s for
--- a busy server), and the editor must not wait for it at start. nil when `$NVIM` is not set.
---@class Terminal.TmuxOwnerCheck
---@field address string The value of `$NVIM`
---@field state "pending"|"checking"|"known"
---@field owner? boolean Once known: true = publish, false = the outer Neovim owns the pane

---@type Terminal.TmuxOwnerCheck|nil
local check = nil

--- Whether this Neovim may still write the pane once its UI is up. `$NVIM` is not looked into here
--- (no process is started at setup); `ready()` finds out before the first publication.
---@param env table<string, string|nil>
---@return boolean ok
---@return string|nil reason
function M.available(env)
  check = nil
  if not Env.inside(env, "tmux") then
    return false, "not running inside tmux ($TMUX is not set)"
  end
  if not Env.set(env.TMUX_PANE) then
    return false, "$TMUX_PANE is not set"
  end
  if Env.set(env.NVIM) then
    check = { address = env.NVIM, state = "pending" }
  end
  return true, nil
end

--- The answer of the nesting check for `this` (ignored when `available` started another since).
---@internal
---@param this Terminal.TmuxOwnerCheck
---@param nested boolean|nil
local function settle(this, nested)
  if check ~= this then
    return
  end
  this.state = "known"
  this.owner = not nested
  local status = require("terminal.status")
  if nested then
    -- The outer Neovim owns the pane: this one never writes it, as if `available` had refused.
    status.drop(M.name)
    return
  end
  if nested == nil then
    -- Unknown ancestry is not a reason to leave the pane without a status: publish, and say so once.
    M.warn_unknown_once()
  end
  -- What was held back while the check ran goes out now.
  status.request()
end

--- Whether the nesting check lets this Neovim publish; starts it the first time it is asked.
---@internal
---@return boolean
local function owns_pane()
  if check == nil then
    return true
  end
  if check.state == "known" then
    return check.owner == true
  end
  if check.state == "pending" then
    local this = check
    this.state = "checking"
    require("terminal.status.nested").nested_async(this.address, function(nested)
      settle(this, nested)
    end)
  end
  return false
end

local warned_unknown = false

---@internal
---@return boolean
local function has_ui()
  return #vim.api.nvim_list_uis() > 0
end

--- One warning per session (in `auto` too) that $NVIM is set but the nesting could not be found out.
---@return nil
function M.warn_unknown_once()
  -- Not for a Neovim without a UI (a script child, `--headless`): it never exports, there is nothing to warn of.
  if warned_unknown or not has_ui() then
    return
  end
  warned_unknown = true
  vim.schedule(function()
    require("terminal.notify").warn(
      "status: could not tell whether $NVIM owns this tmux pane (the outer Neovim did not answer or the "
        .. "process tree is unreadable); exporting the status anyway"
    )
  end)
end

--- Forget the warning that was given (specs).
---@return nil
function M.reset_unknown_warning()
  warned_unknown = false
end

--- Only a Neovim with an attached UI shows anything to the pane's user; a headless one (a
--- script, `--headless "+Lazy! sync"`) leaves the pane's options alone. With `$NVIM` set, not
--- before the nesting check answered (it is started here, the first time a UI is there).
---@return boolean
function M.ready()
  return has_ui() and owns_pane()
end

---@internal
---@param pane string
---@param fields table<string, string>
---@param unset boolean
---@return string[] argv
local function command(pane, fields, unset)
  local argv = { "tmux" }
  local names = vim.tbl_keys(fields)
  table.sort(names)
  for i, name in ipairs(names) do
    if i > 1 then
      argv[#argv + 1] = ";"
    end
    vim.list_extend(argv, { "set-option", "-p" })
    if unset then
      argv[#argv + 1] = "-u"
    end
    vim.list_extend(argv, { "-t", pane, name })
    if not unset then
      argv[#argv + 1] = tmux_word(fields[name])
    end
  end
  return argv
end

--- The pane options for a decoded dataset.
---@param data table
---@return table<string, string>
function M.fields(data)
  local diag = {}
  if (data.e or 0) > 0 then
    diag[#diag + 1] = "E" .. data.e
  end
  if (data.w or 0) > 0 then
    diag[#diag + 1] = "W" .. data.w
  end
  return {
    ["@terminal_mode"] = tostring(data.mode or ""),
    ["@terminal_file"] = tostring(data.file or ""),
    ["@terminal_branch"] = tostring(data.branch or ""),
    ["@terminal_diag"] = table.concat(diag, " "),
    ["@terminal_rec"] = tostring(data.rec or ""),
    ["@terminal_mod"] = data.mod and "+" or "",
  }
end

--- What this exporter publishes, as one string: the delta gate compares this, so a change the pane
--- options do not carry (cwd, filetype, info and hint counts) costs no tmux process.
---@param data table
---@return string
function M.key(data)
  local fields = M.fields(data)
  local names = vim.tbl_keys(fields)
  table.sort(names)
  local parts = {}
  for _, name in ipairs(names) do
    parts[#parts + 1] = fields[name]
  end
  -- NUL cannot occur in a value (the dataset is sanitised), so the parts cannot run together.
  return table.concat(parts, "\0")
end

---@param json string The encoded dataset
---@param data? table The same dataset, already decoded
---@return boolean ok
---@return string|nil err
function M.publish(json, data)
  local pane = vim.env.TMUX_PANE
  if data == nil then
    local ok, decoded = pcall(vim.json.decode, json)
    if not ok or type(decoded) ~= "table" then
      return false, "dataset is not JSON"
    end
    data = decoded
  end
  -- Set before the call: a chain that fails half-way has still written some of the options.
  owned = true
  local res = M.run(command(pane, M.fields(data), false))
  if res.code ~= 0 then
    return false, failure(res)
  end
  return true, nil
end

--- Starts a tmux command without waiting; `on_done(res)` runs on the main loop. Replaceable (specs).
---@type fun(argv: string[], on_done: fun(res: Terminal.ExecResult)): vim.SystemObj|nil
M.spawn = function(argv, on_done)
  local exec = require("terminal.core.exec")
  return exec.spawn(argv, { timeout = exec.configured("status.timeout_ms", 2000) }, on_done)
end

--- The publish in flight (at most one), the newest request that arrived meanwhile, and a counter
--- that `clear` bumps so a late answer from before the clear is ignored.
local inflight ---@type vim.SystemObj|boolean|nil
local pending ---@type { argv: string[], done: fun(ok: boolean, err?: string) }|nil
local epoch = 0

---@internal
---@param argv string[]
---@param done fun(ok: boolean, err?: string)
local function start(argv, done)
  local mine = epoch
  inflight = true
  local proc = M.spawn(argv, function(res)
    if mine ~= epoch then
      return
    end
    inflight = nil
    local queued = pending
    pending = nil
    if res.code ~= 0 then
      -- The caller switches the exporter off: a queued request would only repeat the failure.
      done(false, failure(res))
      return
    end
    done(true)
    if queued then
      start(queued.argv, queued.done)
    end
  end)
  if proc and inflight then
    inflight = proc
  end
end

--- Publish without blocking the editor (a mode change must not wait for tmux). One tmux process
--- runs at a time; a request that comes while it runs replaces any earlier waiting one (the
--- newest dataset wins), and only the requests that actually run are reported to `done`.
---@param json string The encoded dataset
---@param data? table The same dataset, already decoded
---@param done fun(ok: boolean, err?: string) Called on the main loop once the process ended
---@return boolean ok # false when the request is unusable (done is not called then)
---@return string|nil err
function M.publish_async(json, data, done)
  local pane = vim.env.TMUX_PANE
  if data == nil then
    local ok, decoded = pcall(vim.json.decode, json)
    if not ok or type(decoded) ~= "table" then
      return false, "dataset is not JSON"
    end
    data = decoded
  end
  -- Set before the call: a chain that fails half-way has still written some of the options.
  owned = true
  local argv = command(pane, M.fields(data), false)
  if inflight then
    pending = { argv = argv, done = done }
  else
    start(argv, done)
  end
  return true, nil
end

--- Remove the options (this Neovim leaves the pane). Nothing to do when this instance never
--- wrote them.
---@return boolean ok
---@return string|nil err
function M.clear()
  if not owned then
    return true, nil
  end
  owned = false
  -- A publish still running must end before the options go, or it would write them back.
  epoch = epoch + 1
  pending = nil
  if type(inflight) == "table" then
    pcall(function()
      inflight:wait(require("terminal.core.exec").configured("status.timeout_ms", 2000))
    end)
  end
  inflight = nil
  local pane = vim.env.TMUX_PANE
  local res = M.run(command(pane, M.fields({}), true))
  if res.code ~= 0 then
    return false, failure(res)
  end
  return true, nil
end

M._command = command

return M
