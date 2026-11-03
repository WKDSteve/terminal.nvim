---@module 'terminal.repos.classify'
--- The rules of the repository status area, as pure functions: `git status` output -> local state,
--- the newest GitHub Actions run of a commit -> CI state. Nothing here runs a process or reads the
--- editor; `terminal.repos` feeds it the output of `git` and `gh`.
---@see terminal.repos

local M = {}

--- The step a job fails in when the runner's job-started hook (the runner guard of testing.nvim,
--- docs/RUNNER-GUARD.md) refuses it. Measured on the refused runs of streamtap (2026-11-03): the
--- run is `failure`, and in every job the only failed step is "Set up runner" -- no step of the
--- workflow itself ran. A genuine red run fails in a step of the workflow.
--- "Set up job" is the same step on a GitHub-hosted runner.
M.SETUP_STEPS = { ["Set up runner"] = true, ["Set up job"] = true }

--- Display order of the CI states, worst first: the state of a commit with several workflows is
--- the first of these any of them has.
M.CI_ORDER = { "red", "approval", "running", "queued", "cancelled", "green", "skipped", "none" }

---@class Terminal.RepoLocal
---@field branch? string
---@field upstream? string
---@field changed integer Files with a change (staged, unstaged or untracked)
---@field ahead integer
---@field behind integer
---@field gone boolean The upstream branch is gone
---@field state "clean"|"dirty"|"unpushed"|"behind"|"diverged"

--- Parse `git status --porcelain=v1 -b`.
---@param text string
---@return Terminal.RepoLocal
function M.local_state(text)
  local out = { changed = 0, ahead = 0, behind = 0, gone = false, state = "clean" }
  for line in (text or ""):gmatch("[^\r\n]+") do
    if line:sub(1, 2) == "##" then
      local head = line:sub(4)
      local names, info = head:match("^(.-)%s+%[(.-)%]$")
      names = names or head
      local branch, upstream = names:match("^(.-)%.%.%.(.+)$")
      out.branch = branch or names:gsub("^No commits yet on ", "")
      out.upstream = upstream
      if info then
        out.ahead = tonumber(info:match("ahead (%d+)")) or 0
        out.behind = tonumber(info:match("behind (%d+)")) or 0
        out.gone = info:find("gone", 1, true) ~= nil
      end
    else
      out.changed = out.changed + 1
    end
  end
  if out.ahead > 0 and out.behind > 0 then
    out.state = "diverged"
  elseif out.changed > 0 then
    out.state = "dirty"
  elseif out.ahead > 0 then
    out.state = "unpushed"
  elseif out.behind > 0 then
    out.state = "behind"
  end
  return out
end

---@class Terminal.RepoRun
---@field id? integer
---@field status? string `queued`, `in_progress`, `completed`, ...
---@field conclusion? string `success`, `failure`, `cancelled`, ...
---@field name? string
---@field jobs? { conclusion?: string, steps?: { name: string, conclusion?: string }[] }[]

--- Whether a failed run was refused by the runner guard rather than failed by its own steps:
--- at least one failed job, and every failed job failed only in a setup step.
---@param jobs? { conclusion?: string, steps?: { name: string, conclusion?: string }[] }[]
---@return boolean
function M.refused_by_guard(jobs)
  local failed = 0
  for _, job in ipairs(jobs or {}) do
    if job.conclusion == "failure" then
      failed = failed + 1
      local any = false
      for _, step in ipairs(job.steps or {}) do
        if step.conclusion == "failure" then
          any = true
          if not M.SETUP_STEPS[step.name or ""] then
            return false
          end
        end
      end
      if not any then
        return false
      end
    end
  end
  return failed > 0
end

--- The CI state of one run.
---@param run Terminal.RepoRun
---@return "green"|"red"|"running"|"queued"|"approval"|"cancelled"|"skipped"|"none"
function M.run_state(run)
  local status = run.status or ""
  if status == "completed" then
    local c = run.conclusion or ""
    if c == "success" then
      return "green"
    elseif c == "failure" or c == "timed_out" or c == "startup_failure" then
      return M.refused_by_guard(run.jobs) and "approval" or "red"
    elseif c == "cancelled" then
      return "cancelled"
    elseif c == "skipped" or c == "neutral" then
      return "skipped"
    end
    return "red"
  elseif status == "in_progress" then
    return "running"
  elseif status == "" then
    return "none"
  end
  -- queued, waiting, pending, requested
  return "queued"
end

--- The CI state of a commit: the worst state among its runs (workflows).
---@param runs Terminal.RepoRun[]
---@return string
function M.ci_state(runs)
  local seen = {}
  for _, run in ipairs(runs or {}) do
    seen[M.run_state(run)] = true
  end
  for _, name in ipairs(M.CI_ORDER) do
    if seen[name] then
      return name
    end
  end
  return "none"
end

--- The command that approves the commit of a refused run (testing.nvim's runner guard).
--- The name comes from a directory somebody chose and the command is copied to be pasted into a
--- shell: a name with anything but letters, digits, `.`, `_` and `-` gets no command.
---@param repo string Repository name
---@return string|nil command
function M.trust_command(repo)
  if not repo:match("^[%w._-]+$") then
    return nil
  end
  return "testing ci trust " .. repo
end

--- The local half of a row.
---@param l Terminal.RepoLocal
---@return string
function M.local_text(l)
  if l.state == "clean" then
    return "clean"
  end
  local parts = {}
  if l.changed > 0 then
    parts[#parts + 1] = ("%d changed"):format(l.changed)
  end
  if l.ahead > 0 then
    parts[#parts + 1] = ("ahead %d"):format(l.ahead)
  end
  if l.behind > 0 then
    parts[#parts + 1] = ("behind %d"):format(l.behind)
  end
  return table.concat(parts, ", ")
end

M.CI_LABEL = {
  green = "green",
  red = "RED",
  running = "running",
  queued = "queued (runner off?)",
  approval = "waiting for approval",
  cancelled = "cancelled",
  skipped = "skipped",
  none = "no run",
}

return M
