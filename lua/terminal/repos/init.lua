---@module 'terminal.repos'
--- The repository status area: for the repositories of the open terminals, the local state (clean,
--- changed, unpushed) and the state of the newest CI run of the pushed commit (green, red,
--- running, queued, waiting for approval by the runner guard). The data layer; the view is
--- `terminal.repos.panel`, the rules are in `terminal.repos.classify`.
---
--- Both tools are asked through one injectable function (`Terminal.RepoExec`), so the specs hand in
--- a fake `git`/`gh`. Questions are throttled per repository: `git` every few seconds, `gh` once a
--- minute, and a repository whose CI question failed (offline, not logged in) is not asked again
--- before the next CI interval.
---@see terminal.repos.classify

local classify = require("terminal.repos.classify")

local M = {}

--- Smallest time between two `git status` runs of one repository, milliseconds.
M.LOCAL_INTERVAL_MS = 5000
--- Smallest time between two `gh` queries of one repository, milliseconds.
M.CI_INTERVAL_MS = 60000
--- Seconds a single process may run.
M.TIMEOUT_MS = 15000
--- Most failed runs of one commit whose jobs are fetched to tell a guard refusal from a red run.
M.MAX_FAILED_LOOKUPS = 5

---@alias Terminal.RepoExec fun(cmd: string[], cwd: string, on_done: fun(code: integer, stdout: string, stderr: string))

---@class Terminal.RepoRow
---@field root string
---@field name string
---@field local_state? Terminal.RepoLocal
---@field local_error? string
---@field ci string One of `classify.CI_ORDER`, or `unavailable`
---@field ci_error? string Why `ci` is `unavailable`
---@field run_id? integer
---@field run_url? string
---@field sha? string
---@field trust? string The command that approves the commit (only with `ci == "approval"`)
---@field local_at integer
---@field ci_at integer

---@type table<string, Terminal.RepoRow>
local cache = {}

---@return number
local function now_ms()
  return vim.uv.hrtime() / 1e6
end

--- The default executor: a process via `vim.system`, never a shell.
---@type Terminal.RepoExec
function M.default_exec(cmd, cwd, on_done)
  local ok = pcall(
    vim.system,
    cmd,
    { cwd = cwd, text = true, timeout = M.TIMEOUT_MS },
    function(res)
      vim.schedule(function()
        on_done(res.code, res.stdout or "", res.stderr or "")
      end)
    end
  )
  if not ok then
    vim.schedule(function()
      on_done(127, "", "cannot start " .. tostring(cmd[1]))
    end)
  end
end

---@param text string
---@return string
local function first_line(text)
  return (text or ""):match("[^\r\n]+") or ""
end

--- The distinct repository roots of a list of terminal handles, in order of first appearance.
---@param handles { root?: string }[]
---@return string[]
function M.roots_of(handles)
  local seen, out = {}, {}
  for _, h in ipairs(handles) do
    local root = h.root
    if type(root) == "string" and root ~= "" and not seen[root] then
      seen[root] = true
      out[#out + 1] = root
    end
  end
  return out
end

---@param root string
---@return string
local function name_of(root)
  return root:gsub("[/\\]+$", ""):match("([^/\\]+)$") or root
end

---@param root string
---@return Terminal.RepoRow
local function row_of(root)
  local row = cache[root]
  if not row then
    row =
      { root = root, name = name_of(root), ci = "none", local_at = -math.huge, ci_at = -math.huge }
    cache[root] = row
  end
  return row
end

--- Ask `git` for the local state of `row`.
---@param row Terminal.RepoRow
---@param exec Terminal.RepoExec
---@param done fun()
local function refresh_local(row, exec, done)
  exec({ "git", "status", "--porcelain=v1", "-b" }, row.root, function(code, out, err)
    if code == 0 then
      row.local_state = classify.local_state(out)
      row.local_error = nil
    else
      row.local_state = nil
      row.local_error = first_line(err) ~= "" and first_line(err) or "not a git repository"
    end
    done()
  end)
end

---@param text string
---@return any|nil
local function decode(text)
  local ok, value = pcall(vim.json.decode, text)
  return ok and value or nil
end

--- Ask `gh` for the newest push run of the repository and classify it.
---@param row Terminal.RepoRow
---@param exec Terminal.RepoExec
---@param done fun()
local function refresh_ci(row, exec, done)
  local function unavailable(why)
    row.ci, row.ci_error, row.trust, row.run_id, row.run_url = "unavailable", why, nil, nil, nil
    done()
  end
  exec(
    {
      "gh",
      "run",
      "list",
      "--event",
      "push",
      "--limit",
      "10",
      "--json",
      "databaseId,status,conclusion,name,headSha,url",
    },
    row.root,
    function(code, out, err)
      if code ~= 0 then
        local why = first_line(err)
        return unavailable(why ~= "" and why or "gh failed (exit " .. tostring(code) .. ")")
      end
      local list = decode(out)
      if type(list) ~= "table" then
        return unavailable("gh returned no JSON")
      end
      if #list == 0 then
        row.ci, row.ci_error, row.trust, row.run_id, row.run_url, row.sha =
          "none", nil, nil, nil, nil, nil
        return done()
      end
      -- `gh run list` is newest first: the runs of the newest commit are the leading ones with its sha.
      local sha = list[1].headSha
      local runs = {}
      for _, r in ipairs(list) do
        if r.headSha ~= sha then
          break
        end
        runs[#runs + 1] = {
          id = r.databaseId,
          status = r.status,
          conclusion = r.conclusion,
          name = r.name,
          url = r.url,
        }
      end
      row.sha, row.ci_error = sha, nil
      row.trust = nil
      row.ci = classify.ci_state(runs)
      row.run_id, row.run_url = runs[1].id, runs[1].url

      -- A failed run may be a refusal of the runner guard: only the steps of its jobs tell. Every
      -- failed run is looked at (a commit with two refused workflows is waiting for approval, not
      -- red), a few at most.
      local failed = {}
      for _, r in ipairs(runs) do
        if classify.run_state(r) == "red" and #failed < M.MAX_FAILED_LOOKUPS then
          failed[#failed + 1] = r
        end
      end
      if #failed == 0 then
        return done()
      end
      local function finish_ci()
        row.ci = classify.ci_state(runs)
        local shown = runs[1]
        for _, r in ipairs(runs) do
          if classify.run_state(r) == "red" then
            shown = r
            break
          end
        end
        row.run_id, row.run_url = shown.id, shown.url
        row.trust = row.ci == "approval"
            and classify.trust_command(classify.owner_repo_of(runs[1].url) or "", sha)
          or nil
        done()
      end
      local function lookup(i)
        local r = failed[i]
        if not r then
          return finish_ci()
        end
        exec({ "gh", "run", "view", tostring(r.id), "--json", "jobs" }, row.root, function(c2, out2)
          local view = c2 == 0 and decode(out2) or nil
          if type(view) == "table" then
            r.jobs = view.jobs
          end
          lookup(i + 1)
        end)
      end
      lookup(1)
    end
  )
end

---@class Terminal.RepoCollectOpts
---@field exec? Terminal.RepoExec Default `default_exec`
---@field force? boolean Ignore the throttle
---@field has_gh? boolean Test hook: whether `gh` exists (default: `vim.fn.executable("gh") == 1`)
---@field local_interval_ms? integer
---@field ci_interval_ms? integer

--- Refresh the rows of `roots` (throttled) and hand them over, in the order of `roots`.
---@param roots string[]
---@param opts? Terminal.RepoCollectOpts
---@param on_done fun(rows: Terminal.RepoRow[])
---@return nil
function M.collect(roots, opts, on_done)
  opts = opts or {}
  local exec = opts.exec or M.default_exec
  local has_gh = opts.has_gh
  if has_gh == nil then
    has_gh = vim.fn.executable("gh") == 1
  end
  local local_ms = opts.local_interval_ms or M.LOCAL_INTERVAL_MS
  local ci_ms = opts.ci_interval_ms or M.CI_INTERVAL_MS
  local t = now_ms()

  local rows, pending = {}, 0
  local started = false
  local function finish()
    if started and pending == 0 then
      on_done(rows)
    end
  end
  local function job()
    pending = pending + 1
    return function()
      pending = pending - 1
      finish()
    end
  end

  for i, root in ipairs(roots) do
    local row = row_of(root)
    rows[i] = row
    if opts.force or t - row.local_at >= local_ms then
      row.local_at = t
      refresh_local(row, exec, job())
    end
    if not has_gh then
      row.ci, row.ci_error = "unavailable", "gh is not installed"
    elseif opts.force or t - row.ci_at >= ci_ms then
      row.ci_at = t
      refresh_ci(row, exec, job())
    end
  end
  started = true
  finish()
end

--- The repositories of the terminals terminal.nvim knows (all projects).
---@param list fun(all?: boolean): { root?: string }[] `terminal.list`
---@return string[]
function M.open_roots(list)
  return M.roots_of(list(true))
end

--- One line per repository.
---@param row Terminal.RepoRow
---@return string
function M.format(row)
  local loc = row.local_state and classify.local_text(row.local_state)
    or ("? " .. (row.local_error or ""))
  local ci
  if row.ci == "unavailable" then
    ci = "n/a (" .. (row.ci_error or "?") .. ")"
  else
    ci = classify.CI_LABEL[row.ci] or row.ci
  end
  local line = ("%-24s local: %-22s CI: %s"):format(row.name, loc, ci)
  if row.trust then
    line = line .. "   -> " .. row.trust
  end
  return line
end

--- Forget everything (specs).
---@return nil
function M.reset()
  cache = {}
end

return M
