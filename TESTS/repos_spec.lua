---@diagnostic disable: need-check-nil, undefined-field, redundant-parameter
-- TESTS/repos_spec.lua -- the repository status area: the rules (terminal.repos.classify), the
-- data layer with a fake git/gh (terminal.repos) and the panel (terminal.repos.panel).

dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".") .. "/support/env.lua").isolate()

local classify = require("terminal.repos.classify")
local repos = require("terminal.repos")
local panel = require("terminal.repos.panel")

describe("terminal.repos.classify.local_state", function()
  it("a clean branch in sync is clean", function()
    local l = classify.local_state("## main...origin/main\n")
    assert.equals("clean", l.state)
    assert.equals("main", l.branch)
    assert.equals("origin/main", l.upstream)
    assert.equals("clean", classify.local_text(l))
  end)

  it("changed files (staged, unstaged, untracked) make it dirty", function()
    local l = classify.local_state("## main...origin/main\n M a.lua\nA  b.lua\n?? c.lua\n")
    assert.equals("dirty", l.state)
    assert.equals(3, l.changed)
    assert.equals("3 changed", classify.local_text(l))
  end)

  it("commits not pushed are unpushed, not dirty", function()
    local l = classify.local_state("## main...origin/main [ahead 2]\n")
    assert.equals("unpushed", l.state)
    assert.equals(2, l.ahead)
    assert.equals("ahead 2", classify.local_text(l))
  end)

  it("behind and diverged", function()
    assert.equals("behind", classify.local_state("## main...origin/main [behind 3]\n").state)
    local d = classify.local_state("## main...origin/main [ahead 1, behind 4]\n")
    assert.equals("diverged", d.state)
    assert.equals("ahead 1, behind 4", classify.local_text(d))
  end)

  it("dirty and ahead are both named", function()
    local l = classify.local_state("## main...origin/main [ahead 1]\n M a\n")
    assert.equals("dirty", l.state)
    assert.equals("1 changed, ahead 1", classify.local_text(l))
  end)

  it("a branch without upstream and a gone upstream", function()
    local l = classify.local_state("## topic\n")
    assert.equals("topic", l.branch)
    assert.is_nil(l.upstream)
    assert.is_true(classify.local_state("## topic...origin/topic [gone]\n").gone)
  end)

  it("a new repository without commits", function()
    assert.equals("main", classify.local_state("## No commits yet on main\n").branch)
  end)
end)

describe("terminal.repos.classify CI", function()
  local function job(conclusion, ...)
    local steps = {}
    for _, name in ipairs({ ... }) do
      steps[#steps + 1] = { name = name, conclusion = "failure" }
    end
    return { conclusion = conclusion, steps = steps }
  end

  it("maps status and conclusion", function()
    assert.equals("green", classify.run_state({ status = "completed", conclusion = "success" }))
    assert.equals("running", classify.run_state({ status = "in_progress" }))
    assert.equals("queued", classify.run_state({ status = "queued" }))
    assert.equals("queued", classify.run_state({ status = "waiting" }))
    assert.equals(
      "cancelled",
      classify.run_state({ status = "completed", conclusion = "cancelled" })
    )
    assert.equals("skipped", classify.run_state({ status = "completed", conclusion = "skipped" }))
    assert.equals("none", classify.run_state({}))
  end)

  it("a failed run without job data is red", function()
    assert.equals("red", classify.run_state({ status = "completed", conclusion = "failure" }))
  end)

  it("a run whose every failed job failed in the setup step is waiting for approval", function()
    local run = {
      status = "completed",
      conclusion = "failure",
      jobs = { job("failure", "Set up runner"), job("failure", "Set up runner") },
    }
    assert.equals("approval", classify.run_state(run))
  end)

  it("one job failing in a step of the workflow makes it red", function()
    local run = {
      status = "completed",
      conclusion = "failure",
      jobs = { job("failure", "Set up runner"), job("failure", "Run cargo test") },
    }
    assert.equals("red", classify.run_state(run))
  end)

  it("a failed job without a failed step is not a refusal", function()
    local run = { status = "completed", conclusion = "failure", jobs = { job("failure") } }
    assert.equals("red", classify.run_state(run))
  end)

  it("the state of a commit is the worst of its runs", function()
    local green = { status = "completed", conclusion = "success" }
    local red = { status = "completed", conclusion = "failure" }
    local running = { status = "in_progress" }
    assert.equals("red", classify.ci_state({ green, red, running }))
    assert.equals("running", classify.ci_state({ green, running }))
    assert.equals("green", classify.ci_state({ green, green }))
    assert.equals("none", classify.ci_state({}))
  end)

  it("names the approval command after the repository", function()
    assert.equals("testing ci trust streamtap", classify.trust_command("streamtap"))
  end)
end)

--- A fake `git`/`gh`: `script[key]` is `{ code, stdout, stderr }`, key = the command joined by blanks.
---@param script table<string, table>
---@return Terminal.RepoExec exec
---@return string[] calls
local function fake(script)
  local calls = {}
  local function exec(cmd, cwd, on_done)
    local key = table.concat(cmd, " ")
    calls[#calls + 1] = cwd .. ": " .. key
    local r = script[key] or { 1, "", "unexpected: " .. key }
    on_done(r[1], r[2] or "", r[3] or "")
  end
  return exec, calls
end

local LIST =
  "gh run list --event push --limit 10 --json databaseId,status,conclusion,name,headSha,url"
local STATUS = "git status --porcelain=v1 -b"

local function collect(roots, opts)
  local got
  repos.collect(roots, opts, function(rows)
    got = rows
  end)
  return got
end

describe("terminal.repos", function()
  before_each(function()
    repos.reset()
  end)

  it("roots_of lists each root once, in order, and skips handles without one", function()
    local roots =
      repos.roots_of({ { root = "/a" }, {}, { root = "/b" }, { root = "/a" }, { root = "" } })
    assert.same({ "/a", "/b" }, roots)
  end)

  it("reads the local and the CI state of a repository", function()
    local exec = fake({
      [STATUS] = { 0, "## main...origin/main [ahead 1]\n" },
      [LIST] = {
        0,
        vim.json.encode({
          {
            databaseId = 7,
            status = "completed",
            conclusion = "success",
            name = "ci",
            headSha = "abc",
            url = "u1",
          },
        }),
      },
    })
    local rows = collect({ "/r/streamtap" }, { exec = exec, has_gh = true })
    assert.equals(1, #rows)
    assert.equals("streamtap", rows[1].name)
    assert.equals("unpushed", rows[1].local_state.state)
    assert.equals("green", rows[1].ci)
    assert.equals("u1", rows[1].run_url)
    assert.matches("streamtap", repos.format(rows[1]))
    assert.matches("ahead 1", repos.format(rows[1]))
    assert.matches("CI: green", repos.format(rows[1]))
  end)

  it("tells a refusal of the runner guard from a real failure and names the command", function()
    local runs = vim.json.encode({
      {
        databaseId = 9,
        status = "completed",
        conclusion = "failure",
        name = "ci",
        headSha = "def",
        url = "u9",
      },
      {
        databaseId = 8,
        status = "completed",
        conclusion = "success",
        name = "ci",
        headSha = "old",
        url = "u8",
      },
    })
    local refused = vim.json.encode({
      jobs = {
        { conclusion = "failure", steps = { { name = "Set up runner", conclusion = "failure" } } },
        { conclusion = "failure", steps = { { name = "Set up runner", conclusion = "failure" } } },
      },
    })
    local exec = fake({
      [STATUS] = { 0, "## main...origin/main\n" },
      [LIST] = { 0, runs },
      ["gh run view 9 --json jobs"] = { 0, refused },
    })
    local rows = collect({ "/r/streamtap" }, { exec = exec, has_gh = true })
    assert.equals("approval", rows[1].ci)
    assert.equals("testing ci trust streamtap", rows[1].trust)
    assert.matches("waiting for approval", repos.format(rows[1]))
    assert.matches("testing ci trust streamtap", repos.format(rows[1]))

    repos.reset()
    local genuine = vim.json.encode({
      jobs = {
        { conclusion = "failure", steps = { { name = "Run cargo test", conclusion = "failure" } } },
      },
    })
    exec = fake({
      [STATUS] = { 0, "## main...origin/main\n" },
      [LIST] = { 0, runs },
      ["gh run view 9 --json jobs"] = { 0, genuine },
    })
    rows = collect({ "/r/streamtap" }, { exec = exec, has_gh = true })
    assert.equals("red", rows[1].ci)
    assert.is_nil(rows[1].trust)
  end)

  it("only the runs of the newest commit count", function()
    local exec = fake({
      [STATUS] = { 0, "## main\n" },
      [LIST] = {
        0,
        vim.json.encode({
          {
            databaseId = 3,
            status = "completed",
            conclusion = "success",
            name = "ci",
            headSha = "new",
          },
          {
            databaseId = 2,
            status = "completed",
            conclusion = "failure",
            name = "ci",
            headSha = "old",
          },
        }),
      },
    })
    assert.equals("green", collect({ "/r/x" }, { exec = exec, has_gh = true })[1].ci)
  end)

  it(
    "a repository without a run has none, a missing gh or a failing gh is a message, not an error",
    function()
      local exec = fake({ [STATUS] = { 0, "## main\n" }, [LIST] = { 0, "[]" } })
      assert.equals("none", collect({ "/r/a" }, { exec = exec, has_gh = true })[1].ci)

      repos.reset()
      local rows = collect({ "/r/a" }, { exec = exec, has_gh = false })
      assert.equals("unavailable", rows[1].ci)
      assert.matches("gh is not installed", repos.format(rows[1]))

      repos.reset()
      exec = fake({
        [STATUS] = { 0, "## main\n" },
        [LIST] = { 4, "", "error connecting to api.github.com\nsecond line" },
      })
      rows = collect({ "/r/a" }, { exec = exec, has_gh = true })
      assert.equals("unavailable", rows[1].ci)
      assert.equals("error connecting to api.github.com", rows[1].ci_error)
      assert.matches("n/a %(error connecting", repos.format(rows[1]))
    end
  )

  it("a directory that is not a repository shows the git message", function()
    local exec = fake({
      [STATUS] = { 128, "", "fatal: not a git repository (or any of the parent directories): .git" },
      [LIST] = { 1, "", "no git remotes found" },
    })
    local rows = collect({ "/r/none" }, { exec = exec, has_gh = true })
    assert.is_nil(rows[1].local_state)
    assert.matches("not a git repository", repos.format(rows[1]))
  end)

  it("throttles: a second collect inside the interval asks nobody, force asks again", function()
    local exec, calls = fake({ [STATUS] = { 0, "## main\n" }, [LIST] = { 0, "[]" } })
    collect({ "/r/a" }, { exec = exec, has_gh = true })
    assert.equals(2, #calls)
    collect({ "/r/a" }, { exec = exec, has_gh = true })
    assert.equals(2, #calls)
    collect({ "/r/a" }, { exec = exec, has_gh = true, force = true })
    assert.equals(4, #calls)
  end)

  it("the local question has a shorter interval than the CI question", function()
    local exec, calls = fake({ [STATUS] = { 0, "## main\n" }, [LIST] = { 0, "[]" } })
    collect({ "/r/a" }, { exec = exec, has_gh = true })
    -- a zero local interval asks git again; the CI interval (default 60 s) holds gh back
    collect({ "/r/a" }, { exec = exec, has_gh = true, local_interval_ms = 0 })
    assert.equals(3, #calls)
    assert.matches("git status", calls[3])
  end)

  it("answers once for several repositories and keeps their order", function()
    local exec = fake({ [STATUS] = { 0, "## main\n" }, [LIST] = { 0, "[]" } })
    local n = 0
    repos.collect({ "/r/b", "/r/a" }, { exec = exec, has_gh = true }, function(rows)
      n = n + 1
      assert.equals("b", rows[1].name)
      assert.equals("a", rows[2].name)
    end)
    assert.equals(1, n)
  end)

  it("answers at once when nothing is due", function()
    local n = 0
    repos.collect({}, { exec = fake({}), has_gh = true }, function()
      n = n + 1
    end)
    assert.equals(1, n)
  end)
end)

describe("terminal.repos.panel", function()
  before_each(function()
    repos.reset()
    panel.close()
  end)
  after_each(function()
    panel.close()
  end)

  it("lines say what to do when there is no repository", function()
    assert.matches("open a terminal", panel.lines({})[1])
  end)

  it("opens a float with one line per repository and closes with q", function()
    local exec =
      fake({ [STATUS] = { 0, "## main...origin/main [ahead 1]\n" }, [LIST] = { 0, "[]" } })
    local buf = panel.open({
      timer = false,
      list = function()
        return { { root = "/r/alpha" }, { root = "/r/beta" } }
      end,
      collect = { exec = exec, has_gh = true },
    })
    assert.is_true(panel.is_open())
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.equals(2, #lines)
    assert.matches("alpha", lines[1])
    assert.matches("beta", lines[2])
    assert.matches("ahead 1", lines[1])
    vim.api.nvim_feedkeys("q", "x", false)
    assert.is_false(panel.is_open())
  end)

  it("y copies the approval command of the line under the cursor", function()
    local runs = vim.json.encode({
      {
        databaseId = 9,
        status = "completed",
        conclusion = "failure",
        name = "ci",
        headSha = "d",
        url = "u",
      },
    })
    local refused = vim.json.encode({
      jobs = {
        { conclusion = "failure", steps = { { name = "Set up runner", conclusion = "failure" } } },
      },
    })
    local exec = fake({
      [STATUS] = { 0, "## main\n" },
      [LIST] = { 0, runs },
      ["gh run view 9 --json jobs"] = { 0, refused },
    })
    panel.open({
      timer = false,
      list = function()
        return { { root = "/r/streamtap" } }
      end,
      collect = { exec = exec, has_gh = true },
    })
    vim.fn.setreg("+", "")
    vim.fn.setreg('"', "")
    vim.api.nvim_feedkeys("y", "x", false)
    assert.equals("testing ci trust streamtap", vim.fn.getreg('"'))
  end)
end)
