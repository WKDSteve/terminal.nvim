---@diagnostic disable: need-check-nil, undefined-field, redundant-parameter
-- need-check-nil, undefined-field and redundant-parameter are off for the whole file: a nil in a spec body fails the next assertion anyway, luassert's assert.* and the stubbed vim.* fields are not in the annotations, and luassert takes a failure message as its last argument, which its type stub does not declare.
-- TESTS/api_spec.lua -- the public facade (`require("terminal")`) on the native backend.

-- Hermetic: no multiplexer variables from the terminal the specs are run in.
dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".") .. "/support/env.lua").isolate()

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local jobs = dofile(here .. "/support/jobs.lua")

describe("terminal (facade)", function()
  local terminal
  local original_notify = vim.notify
  local notices

  before_each(function()
    for _, mod in ipairs({
      "terminal",
      "terminal.config",
      "terminal.backends.native",
      "terminal.bindings",
    }) do
      package.loaded[mod] = nil
    end
    notices = {}
    -- Test double: capture what would be shown to the user; restored in after_each.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function(msg, level)
      notices[#notices + 1] = { msg = msg, level = level }
    end
    terminal = require("terminal")
    -- Commands and keymaps are not the subject here; the sleeper is the terminal's job.
    terminal.setup({
      shell = jobs.sleeper(),
      start_insert = false,
      commands = false,
      keymaps = { preset = false },
    })
  end)

  after_each(function()
    for _, h in ipairs(terminal.list(true)) do
      jobs.settle()
      terminal.close({ name = h.name })
    end
    vim.cmd("silent! tabonly")
    vim.cmd("silent! only")
    -- Restore the original.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = original_notify
  end)

  it("setup resolves the native backend and reports it", function()
    local s = terminal.status()
    assert.is_true(s.ready)
    assert.equals("native", s.backend)
    assert.equals(0, s.terminals)
  end)

  it("falls back to native when a named backend does not exist yet", function()
    terminal.setup({ backend = "tmux", commands = false, keymaps = { preset = false } })
    assert.equals("native", terminal.status().backend)
    vim.wait(100) -- the note is scheduled
    local found = false
    for _, n in ipairs(notices) do
      if n.msg:find("tmux", 1, true) then
        found = true
      end
    end
    assert.is_true(found)
  end)

  it("setup does not look for wezterm or tmux on $PATH unless the config names them", function()
    local looked = {}
    local original = vim.fn.executable
    -- Test double: record which executables setup() asks for; restored below.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.executable = function(name)
      looked[#looked + 1] = name
      return original(name)
    end
    local saved_wez, saved_tmux, saved_pane = vim.env.WEZTERM_PANE, vim.env.TMUX, vim.env.TMUX_PANE
    vim.env.WEZTERM_PANE, vim.env.TMUX, vim.env.TMUX_PANE = "7", "/tmp/tmux-1/default,1,0", "%1"
    terminal.setup({ commands = false, keymaps = { preset = false } })
    vim.env.WEZTERM_PANE, vim.env.TMUX, vim.env.TMUX_PANE = saved_wez, saved_tmux, saved_pane
    -- Restore the original.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.executable = original
    assert.is_false(vim.tbl_contains(looked, "wezterm"))
    assert.is_false(vim.tbl_contains(looked, "tmux"))
  end)

  it("a failing part of setup does not leave status and navigation unconfigured", function()
    local saved_pane = vim.env.WEZTERM_PANE
    vim.env.WEZTERM_PANE = "7"
    package.loaded["terminal.bindings"] = {
      setup = function()
        error("boom")
      end,
    }
    package.loaded["terminal.navigate"] = nil
    terminal.setup({ commands = false, keymaps = { preset = false } })
    vim.env.WEZTERM_PANE = saved_pane
    vim.wait(100)
    assert.same({ "wezterm" }, require("terminal.navigate").active())
    local told = false
    for _, n in ipairs(notices) do
      if n.msg:find("bindings failed", 1, true) then
        told = true
      end
    end
    assert.is_true(told)
    package.loaded["terminal.bindings"] = nil
  end)

  it("a bad auto_insert event is reported and does not break setup", function()
    terminal.setup({
      commands = false,
      keymaps = { preset = false },
      auto_insert = { enable = true, events = { "TermEnterr" } },
    })
    vim.wait(100)
    assert.is_true(terminal.status().ready)
    local told = false
    for _, n in ipairs(notices) do
      if n.msg:find("TermEnterr", 1, true) then
        told = true
      end
    end
    assert.is_true(told)
  end)

  it("toggle on a native terminal that is visible elsewhere still enters Insert mode", function()
    terminal.setup({
      shell = jobs.sleeper(),
      start_insert = true,
      commands = false,
      keymaps = { preset = false },
    })
    terminal.open({ layout = "vsplit" })
    jobs.settle()
    vim.cmd("wincmd p") -- focus leaves the terminal, it stays visible
    local starts = 0
    local original = vim.cmd
    -- Test double: count the startinsert commands; restored below.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.cmd = function(command, ...)
      if command == "startinsert" then
        starts = starts + 1
      end
      return original(command, ...)
    end
    local ok, err = pcall(terminal.toggle)
    -- Restore the original.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.cmd = original
    assert(ok, err)
    assert.equals(1, starts)
  end)

  describe("open / toggle / hide / close", function()
    it("open creates the default terminal once and returns the same handle again", function()
      local a = terminal.open()
      local b = terminal.open()
      assert.equals("main", a.name)
      assert.equals(a.id, b.id)
      assert.equals(1, #terminal.list())
    end)

    it("open without focus keeps the current window current", function()
      local before = vim.api.nvim_get_current_win()
      local h = terminal.open({ focus = false })
      assert.equals(before, vim.api.nvim_get_current_win())
      assert.is_true(#vim.fn.win_findbuf(h.bufnr) > 0)
    end)

    it("toggle: hides a focused terminal, shows a hidden one, creates a missing one", function()
      terminal.toggle()
      local h = terminal.list()[1]
      assert.is_not_nil(h)
      assert.equals(1, #vim.fn.win_findbuf(h.bufnr))

      jobs.settle()
      terminal.toggle() -- focused -> hide
      assert.equals(0, #vim.fn.win_findbuf(h.bufnr))
      assert.equals(1, #terminal.list(), "hiding keeps the terminal")

      jobs.settle()
      terminal.toggle() -- hidden -> show
      assert.equals(1, #vim.fn.win_findbuf(h.bufnr))
      assert.equals(1, #terminal.list())
    end)

    it("toggle on a visible but unfocused terminal focuses it instead of hiding it", function()
      local h = terminal.open()
      vim.cmd("wincmd p")
      assert.not_equals(h.bufnr, vim.api.nvim_get_current_buf())
      terminal.toggle()
      assert.equals(h.bufnr, vim.api.nvim_get_current_buf())
    end)

    it("a count picks the terminal of that number", function()
      terminal.toggle({ count = 3 })
      local names = vim.tbl_map(function(h)
        return h.name
      end, terminal.list())
      assert.same({ "3" }, names)
    end)

    it("an explicit name wins over a count", function()
      terminal.open({ name = "build", count = 3 })
      assert.equals("build", terminal.list()[1].name)
    end)

    it("honours a per-call layout", function()
      local h = terminal.open({ layout = "vsplit" })
      assert.equals("vsplit", h.layout)
      assert.equals("", vim.api.nvim_win_get_config(vim.fn.win_findbuf(h.bufnr)[1]).relative)
    end)

    it("hide returns false for a terminal that does not exist", function()
      assert.is_false(terminal.hide({ name = "ghost" }))
    end)

    it("close removes the terminal; closing a missing one returns false", function()
      terminal.open()
      assert.is_true(terminal.close())
      assert.equals(0, #terminal.list())
      assert.is_false(terminal.close())
    end)

    it("an exited terminal is replaced on the next open", function()
      terminal.setup({
        shell = jobs.exit_with(0),
        on_exit = "keep",
        commands = false,
        keymaps = { preset = false },
        start_insert = false,
      })
      local first = terminal.open()
      assert.is_true(jobs.wait(function()
        return first.exited == true
      end))
      terminal.setup({
        shell = jobs.sleeper(),
        commands = false,
        keymaps = { preset = false },
        start_insert = false,
      })
      local second = terminal.open()
      assert.is_not_nil(second)
      assert.not_equals(first.bufnr, second.bufnr)
      assert.is_false(second.exited == true)
    end)

    -- 'winfixbuf' (Neovim 0.10+) forbids showing another buffer in the last window of the editor,
    -- which is what closing it needs. Registered only where the option exists.
    if vim.fn.exists("+winfixbuf") == 1 then
      describe("an earlier terminal under the same name that cannot be closed", function()
        local pinned

        after_each(function()
          if pinned and vim.api.nvim_win_is_valid(pinned) then
            vim.wo[pinned].winfixbuf = false
          end
          pinned = nil
        end)

        it("makes open fail with the reason and leaves it registered", function()
          terminal.setup({
            shell = jobs.exit_with(0),
            on_exit = "keep",
            commands = false,
            keymaps = { preset = false },
            start_insert = false,
          })
          local first = terminal.open({ layout = "tab" })
          assert.is_true(jobs.wait(function()
            return first.exited == true
          end))
          -- The exited terminal alone in the only window of the editor, pinned to its buffer.
          vim.cmd("1tabclose")
          assert.equals(1, #vim.api.nvim_list_tabpages())
          pinned = vim.fn.win_findbuf(first.bufnr)[1]
          vim.wo[pinned].winfixbuf = true
          jobs.settle()

          local second, err = terminal.open({ layout = "tab" })
          assert.is_nil(second)
          assert.truthy(
            tostring(err):find("cannot replace the earlier one", 1, true),
            tostring(err)
          )
          assert.truthy(tostring(err):find("E1513", 1, true), tostring(err))
          vim.wait(100) -- the report is scheduled
          local reported = false
          for _, n in ipairs(notices) do
            reported = reported or n.msg:find(err, 1, true) ~= nil
          end
          assert.is_true(reported, "the failure is shown to the user")
          -- Not orphaned: the registry still holds that one terminal, with its buffer and window.
          local all = terminal.list(true)
          assert.equals(1, #all)
          assert.equals(first, all[1])
          assert.is_true(vim.api.nvim_buf_is_valid(first.bufnr))
          assert.equals(1, #vim.fn.win_findbuf(first.bufnr))

          -- Once the obstacle is gone the same call replaces it.
          vim.wo[pinned].winfixbuf = false
          terminal.setup({
            shell = jobs.sleeper(),
            commands = false,
            keymaps = { preset = false },
            start_insert = false,
          })
          local third = terminal.open({ layout = "tab" })
          assert.is_not_nil(third)
          assert.not_equals(first.bufnr, third.bufnr)
          assert.is_false(vim.api.nvim_buf_is_valid(first.bufnr))
          all = terminal.list(true)
          assert.equals(1, #all)
          assert.equals(third, all[1])
        end)
      end)
    end
  end)

  describe("send", function()
    local function eol()
      return vim.fn.has("win32") == 1 and "\r" or "\n"
    end

    it("creates the run terminal on demand and writes the text as typed", function()
      local ok, err
      local sent = jobs.record_sends(function()
        ok, err = terminal.send("some text")
      end)
      assert.is_true(ok, err)
      assert.equals(1, #sent)
      assert.equals("some text", sent[1].text)
      assert.equals(terminal.list()[1].job, sent[1].job)
      local names = vim.tbl_map(function(h)
        return h.name
      end, terminal.list())
      assert.same({ "run" }, names)
    end)

    it("presses Enter only with newline = true", function()
      local sent = jobs.record_sends(function()
        terminal.send("ls", { newline = true })
      end)
      assert.equals("ls" .. eol(), sent[1].text)
    end)

    it("on Windows every line break of the text is an Enter (CR)", function()
      local module = "lib.nvim.cross.platform.is_windows"
      local real = package.loaded[module]
      package.loaded[module] = function()
        return true
      end
      local sent = jobs.record_sends(function()
        terminal.send("a\nb\r\nc", { newline = true })
      end)
      package.loaded[module] = real
      assert.equals("a\rb\rc\r", sent[1].text)
    end)

    it("elsewhere the line breaks of the text stay as they are", function()
      local module = "lib.nvim.cross.platform.is_windows"
      local real = package.loaded[module]
      package.loaded[module] = function()
        return false
      end
      local sent = jobs.record_sends(function()
        terminal.send("a\nb", { newline = true })
      end)
      package.loaded[module] = real
      assert.equals("a\nb\n", sent[1].text)
    end)

    it("sends to the terminal of the given name", function()
      jobs.record_sends(function()
        terminal.send("x", { name = "repl" })
      end)
      assert.same(
        { "repl" },
        vim.tbl_map(function(h)
          return h.name
        end, terminal.list())
      )
    end)

    it("does not steal focus by default", function()
      local before = vim.api.nvim_get_current_win()
      jobs.record_sends(function()
        terminal.send("x")
      end)
      assert.equals(before, vim.api.nvim_get_current_win())
    end)

    it("rejects a non-string", function()
      local ok, err = terminal.send(42)
      assert.is_false(ok)
      assert.truthy(err)
    end)
  end)

  describe("run", function()
    it("direct: the command is the job and its exit code reaches on_exit", function()
      local code
      local ok = terminal.run(jobs.exit_with(3), {
        direct = true,
        name = "job",
        on_exit = function(c)
          code = c
        end,
      })
      assert.is_true(ok)
      assert.is_true(jobs.wait(function()
        return code ~= nil
      end))
      assert.equals(3, code)
    end)

    it("direct: runs again under the same name and replaces the earlier terminal", function()
      terminal.run(jobs.sleeper(), { direct = true, name = "job", focus = false })
      local first = terminal.list()[1]
      jobs.settle()
      terminal.run(jobs.sleeper(), { direct = true, name = "job", focus = false })
      assert.equals(1, #terminal.list())
      assert.not_equals(first.bufnr, terminal.list()[1].bufnr)
    end)

    it(
      "direct: close = always removes the terminal when the job ends, on_open sees the handle",
      function()
        local opened, code
        terminal.run(jobs.exit_with(0), {
          direct = true,
          name = "tui",
          close = "always",
          on_open = function(h)
            opened = h
          end,
          on_exit = function(c)
            code = c
          end,
        })
        assert.is_not_nil(opened)
        assert.equals("tui", opened.name)
        assert.is_true(jobs.wait(function()
          return code ~= nil and #terminal.list() == 0
        end))
        assert.equals(0, code)
      end
    )

    it("direct: close = success keeps a failed job readable", function()
      local code
      terminal.run(jobs.exit_with(4), {
        direct = true,
        name = "tui",
        close = "success",
        on_exit = function(c)
          code = c
        end,
      })
      assert.is_true(jobs.wait(function()
        return code ~= nil
      end))
      vim.wait(100)
      assert.equals(1, #terminal.list())
      assert.equals(4, terminal.list()[1].exit_code)
    end)

    it("direct: hidden and shown again, the window keeps its title and float overrides", function()
      local _, _, h = terminal.run(jobs.sleeper(), {
        direct = true,
        name = "git",
        layout = "float",
        title = "lazygit",
        float = { width = 0.5 },
      })
      jobs.settle()
      assert.is_true((terminal.hide({ name = "git" })))
      assert.truthy(terminal.open({ name = "git" }))
      local cfg = vim.api.nvim_win_get_config(vim.fn.win_findbuf(h.bufnr)[1])
      assert.truthy(vim.inspect(cfg.title):find("lazygit", 1, true))
      assert.is_true(cfg.width < vim.o.columns * 0.6)
    end)

    it("direct: title, cwd and float overrides reach the window and the job", function()
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, "p")
      -- what jobstart is asked for: the directory of the JOB, not only what the handle remembers
      local started_in
      local jobstart = vim.fn.jobstart
      -- Test double: record the options jobstart is given; restored below.
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.fn.jobstart = function(command, job_opts)
        started_in = job_opts and job_opts.cwd
        return jobstart(command, job_opts)
      end
      local _, _, h = terminal.run(jobs.sleeper(), {
        direct = true,
        name = "git",
        title = "lazygit",
        cwd = dir,
        float = { width = 0.5, height = 0.5 },
      })
      -- Restore the original.
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.fn.jobstart = jobstart
      -- Assert first, clean up always: a failed assertion must not leave the directory behind.
      local ok, err = pcall(function()
        local win = vim.fn.win_findbuf(h.bufnr)[1]
        local cfg = vim.api.nvim_win_get_config(win)
        assert.truthy(vim.inspect(cfg.title):find("lazygit", 1, true))
        assert.is_true(cfg.width < vim.o.columns * 0.6)
        assert.equals(dir, h.cwd, "the job starts in the directory that was asked for")
        assert.equals(dir, started_in, "jobstart got the directory")
      end)
      vim.fn.delete(dir, "d")
      if not ok then
        error(err, 0)
      end
    end)

    it("direct: needs an argv list", function()
      local ok, err = terminal.run("make test", { direct = true })
      assert.is_false(ok)
      assert.truthy(err:find("argv", 1, true))
      assert.equals(0, #terminal.list())
    end)

    it("an argv with a line break is refused before any terminal is started", function()
      local ok, err = terminal.run({ "echo", "a\nrm -rf /" })
      assert.is_false(ok)
      assert.truthy(err)
      assert.equals(0, #terminal.list())
    end)

    it("refuses an empty command", function()
      assert.is_false((terminal.run("")))
      assert.is_false((terminal.run({})))
    end)

    it("an argv is quoted for the shell and typed into the run terminal with Enter", function()
      local ok, err
      local sent = jobs.record_sends(function()
        ok, err = terminal.run({ "echo", "a b", "it's" })
      end)
      assert.is_true(ok, err)
      assert.equals("run", terminal.list()[1].name)
      -- the shell is the sleeper program (a POSIX-style name), so POSIX quoting applies
      assert.equals(
        [[echo 'a b' 'it'\''s']] .. (vim.fn.has("win32") == 1 and "\r" or "\n"),
        sent[1].text
      )
    end)

    it("a string is typed exactly as given", function()
      local sent = jobs.record_sends(function()
        terminal.run("make test && echo $HOME")
      end)
      assert.equals(
        "make test && echo $HOME" .. (vim.fn.has("win32") == 1 and "\r" or "\n"),
        sent[1].text
      )
    end)
  end)

  describe("error contract", function()
    local function said(fragment)
      vim.wait(100, function()
        return false
      end)
      for _, n in ipairs(notices) do
        if n.msg:find(fragment, 1, true) then
          return true
        end
      end
      return false
    end

    it("a target of the wrong shape fails with a reason, reports it, creates nothing", function()
      local bad = {
        { "x", "target must be a table" },
        { { name = "" }, "target.name must be a non-empty string" },
        { { name = 3 }, "target.name must be a non-empty string" },
        { { layout = "diagonal" }, "unknown layout" },
        { { focus = "yes" }, "target.focus must be a boolean" },
        { { dir = "" }, "target.dir must be a non-empty string" },
        { { dir = 3 }, "target.dir must be a non-empty string" },
        { { count = "3" }, "count must be a number from 1 up" },
        { { count = -2 }, "count must be a number from 1 up" },
      }
      for _, case in ipairs(bad) do
        local handle, err = terminal.open(case[1])
        assert.is_nil(handle, vim.inspect(case[1]))
        assert.truthy(err:find(case[2], 1, true), vim.inspect(case[1]) .. ": " .. tostring(err))
        local ok, terr = terminal.toggle(case[1])
        assert.is_false(ok)
        assert.equals(err, terr)
        local hidden, herr = terminal.hide(case[1])
        assert.is_false(hidden)
        assert.equals(err, herr)
        local closed, cerr = terminal.close(case[1])
        assert.is_false(closed)
        assert.equals(err, cerr)
      end
      assert.is_true(said("target must be a table"))
      assert.equals(0, #terminal.list(true))
    end)

    it("hide and close of a terminal that does not exist say so without a notification", function()
      local hidden, herr = terminal.hide({ name = "ghost" })
      assert.is_false(hidden)
      assert.equals("no terminal 'ghost' in this project", herr)
      local closed, cerr = terminal.close({ name = "ghost" })
      assert.is_false(closed)
      assert.equals("no terminal 'ghost' in this project", cerr)
      assert.is_false(said("ghost"), "the caller asked a question; it was answered")
    end)

    it("toggle returns true when it created, showed or hid the terminal", function()
      assert.is_true((terminal.toggle()))
      jobs.settle()
      assert.is_true((terminal.toggle()))
      jobs.settle()
      assert.is_true((terminal.toggle()))
    end)

    it("send of something that is not text fails, says so, and starts nothing", function()
      -- Deliberately wrong type: the case checks the guard.
      ---@diagnostic disable-next-line: param-type-mismatch
      local ok, err = terminal.send(5)
      assert.is_false(ok)
      assert.equals("send: text must be a string", err)
      assert.is_true(said("send: text must be a string"))
      assert.equals(0, #terminal.list(true))
    end)

    it("count 0 (no count typed) sends and runs in the run terminal, like no count", function()
      local sent = jobs.record_sends(function()
        assert.is_true((terminal.send("a", { count = 0 })))
      end)
      assert.equals(1, #sent)
      local names = vim.tbl_map(function(h)
        return h.name
      end, terminal.list())
      assert.same({ "run" }, names)
      -- a real count still picks its own terminal
      jobs.record_sends(function()
        assert.is_true((terminal.send("a", { count = 2 })))
      end)
      names = vim.tbl_map(function(h)
        return h.name
      end, terminal.list())
      table.sort(names)
      assert.same({ "2", "run" }, names)
    end)

    it("run direct needs strings: a number among the words fails with a reason", function()
      -- Deliberately wrong type: the case checks the guard.
      ---@diagnostic disable-next-line: assign-type-mismatch
      local ok, err = terminal.run({ "sleep", 5 }, { direct = true })
      assert.is_false(ok)
      assert.truthy(err:find("argument 2", 1, true), tostring(err))
      assert.is_true(said("argument 2"))
      assert.equals(0, #terminal.list(true))
      ok, err = terminal.run({ "a\0b" }, { direct = true })
      assert.is_false(ok)
      assert.truthy(err:find("argument 1", 1, true), tostring(err))
    end)

    it('run direct: an empty ARGUMENT is data (rg "" file), an empty program is not', function()
      local argv = jobs.exit_with(0)
      table.insert(argv, "")
      local ok, err = terminal.run(argv, { direct = true, name = "empty-arg" })
      assert.is_true(ok, tostring(err))
      assert.equals(1, #terminal.list())
      ok, err = terminal.run({ "" }, { direct = true, name = "empty-program" })
      assert.is_false(ok)
      assert.truthy(err:find("argument 1", 1, true), tostring(err))
      assert.equals(1, #terminal.list(), "the empty program started nothing")
    end)

    it("run direct hands an empty argument to the program, in its place", function()
      -- Not only accepted: the program receives it. A child Neovim writes what it was given.
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, "p")
      local script, out = vim.fs.normalize(dir .. "/dump.lua"), vim.fs.normalize(dir .. "/args.txt")
      vim.fn.writefile({
        ('local f = assert(io.open(%q, "w"))'):format(out),
        'for i = 1, 3 do f:write("<", tostring(arg[i]), ">\\n") end',
        "f:close()",
      }, script)
      local ok, err = terminal.run({
        vim.v.progpath,
        "-n",
        "-i",
        "NONE",
        "--headless",
        "-u",
        "NONE",
        "-l",
        script,
        "",
        "x",
        "",
      }, { direct = true, name = "empty-args-arrive" })
      assert.is_true(ok, tostring(err))
      local written = jobs.wait(function()
        return vim.uv.fs_stat(out) ~= nil
      end, 20000)
      local got = written and vim.fn.readfile(out) or {}
      vim.fn.delete(dir, "rf")
      assert.is_true(written, "the program ran and wrote its arguments")
      assert.same({ "<>", "<x>", "<>" }, got)
    end)

    it("run refuses a hole in the argv instead of starting it without the words behind", function()
      -- `ipairs` stops at the hole: `{ "git", "clean", "-fd", nil, "--dry-run" }` would have run
      -- `git clean -fd` for real
      local opt = nil
      local before = #terminal.list()
      local ok, err = terminal.run({ "git", "clean", "-fd", opt, "--dry-run" }, { direct = true })
      assert.is_false(ok)
      assert.truthy(err and err:find("argument 4", 1, true), tostring(err))
      ok, err = terminal.run({ "git", "clean", "-fd", opt, "--dry-run" })
      assert.is_false(ok)
      assert.truthy(err and err:find("argument 4", 1, true), tostring(err))
      assert.equals(before, #terminal.list(), "nothing was started")
    end)

    it("run reports its failures with the same 'run:' prefix it shows", function()
      local ok, err = terminal.run({})
      assert.is_false(ok)
      assert.truthy(err:find("^run: "), tostring(err))
      ok, err = terminal.run({ "echo", "a\nb" })
      assert.is_false(ok)
      assert.truthy(err:find("^run: "), tostring(err))
    end)

    it("send and run with options of the wrong type fail instead of raising", function()
      local ok, err = terminal.send("x", "y")
      assert.is_false(ok)
      assert.truthy(err:find("opts must be a table", 1, true))
      ok, err = terminal.run("x", 3)
      assert.is_false(ok)
      assert.truthy(err:find("opts must be a table", 1, true))
      assert.equals(0, #terminal.list(true))
    end)

    it("run: close must be always, success or never", function()
      local ok, err = terminal.run(jobs.sleeper(), { direct = true, close = "sometimes" })
      assert.is_false(ok)
      assert.truthy(err:find("close must be always, success or never", 1, true))
      assert.equals(0, #terminal.list(true))
    end)

    it("a callback that raises is reported and does not take the terminal with it", function()
      local code
      local ok, _, handle = terminal.run(jobs.exit_with(0), {
        direct = true,
        name = "cb",
        close = "never",
        on_open = function()
          error("open boom")
        end,
        on_exit = function(c)
          code = c
          error("exit boom")
        end,
      })
      assert.is_true(ok)
      assert.is_not_nil(handle)
      assert.is_true(jobs.wait(function()
        return code ~= nil
      end))
      assert.is_true(said("on_open failed"))
      assert.is_true(said("on_exit failed"))
      assert.equals(1, #terminal.list())
    end)

    it("returned handles are live references: the registry's own record", function()
      local a = terminal.open()
      local b = terminal.list()[1]
      assert.equals(a, b)
    end)
  end)

  describe("a directory per call (target.dir)", function()
    local base, project, docs, api_dir, saved_cwd

    ---@return string[]
    local function names(all)
      local out = vim.tbl_map(function(h)
        return h.name
      end, terminal.list(all))
      table.sort(out)
      return out
    end

    before_each(function()
      saved_cwd = vim.fn.getcwd()
      base = vim.fs.normalize(vim.fn.tempname() .. "-terminal-dir")
      project = base .. "/proj"
      docs = project .. "/docs"
      api_dir = docs .. "/api"
      vim.fn.mkdir(project .. "/.git", "p")
      vim.fn.mkdir(api_dir, "p")
      vim.fn.writefile({ "x" }, docs .. "/guide.md")
      vim.cmd("cd " .. vim.fn.fnameescape(project))
    end)

    after_each(function()
      -- The terminals of this block belong to `project`: close them from inside it, before the
      -- cwd goes back (the outer after_each closes by name in the project it is in).
      vim.cmd("cd " .. vim.fn.fnameescape(project))
      for _, h in ipairs(terminal.list(true)) do
        jobs.settle()
        terminal.close({ name = h.name })
      end
      vim.cmd("cd " .. vim.fn.fnameescape(saved_cwd))
      vim.fn.delete(base, "rf")
    end)

    it("open starts a terminal in the folder, named after it, in the folder's project", function()
      local started_in
      local jobstart = vim.fn.jobstart
      -- Test double: record the options jobstart is given; restored below.
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.fn.jobstart = function(command, job_opts)
        started_in = job_opts and job_opts.cwd
        return jobstart(command, job_opts)
      end
      local h, err = terminal.open({ dir = docs, focus = false })
      -- Restore the original.
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.fn.jobstart = jobstart
      assert.is_not_nil(h, err)
      assert.equals("docs/", h.name)
      assert.equals(docs, h.cwd, "the terminal remembers the folder")
      assert.equals(docs, started_in, "the job starts in the folder")
      local main = terminal.open({ focus = false })
      assert.equals(main.root, h.root, "it belongs to the project of the folder")
      assert.same({ "docs/", "main" }, names())
    end)

    it("a folder deeper down is named by its path below the project root", function()
      local h = terminal.open({ dir = api_dir, focus = false })
      assert.equals("docs/api/", h.name)
      assert.equals(api_dir, h.cwd)
    end)

    it("the same folder is the same terminal, however it is spelled", function()
      local a = terminal.open({ dir = docs, focus = false })
      local b = terminal.open({ dir = "docs", focus = false })
      local c = terminal.open({ dir = docs .. "/api/..", focus = false })
      assert.equals(a.id, b.id)
      assert.equals(a.id, c.id)
      assert.equals(1, #terminal.list())
    end)

    it("a folder named like the default, the run or a counted terminal is still its own", function()
      for _, name in ipairs({ "main", "run", "3" }) do
        vim.fn.mkdir(project .. "/" .. name, "p")
      end
      local main = terminal.open({ focus = false })
      local third = terminal.open({ count = 3, focus = false })
      jobs.record_sends(function()
        terminal.send("x")
      end)
      local in_main = terminal.open({ dir = "main", focus = false })
      local in_three = terminal.open({ dir = "3", focus = false })
      local in_run = terminal.open({ dir = "run", focus = false })
      assert.not_equals(main.id, in_main.id)
      assert.not_equals(third.id, in_three.id)
      assert.equals(project .. "/main", in_main.cwd)
      assert.equals(project .. "/3", in_three.cwd)
      assert.equals(project .. "/run", in_run.cwd)
      assert.same({ "3", "3/", "main", "main/", "run", "run/" }, names())
    end)

    it("the project root as the directory is the project's own terminal", function()
      local main = terminal.open({ focus = false })
      local same = terminal.open({ dir = project, focus = false })
      assert.equals("main", same.name)
      assert.equals(main.id, same.id)
    end)

    it("a name or a count still names the terminal; the directory is where it starts", function()
      local named = terminal.open({ dir = docs, name = "build", focus = false })
      assert.equals("build", named.name)
      assert.equals(docs, named.cwd)
      local counted = terminal.open({ dir = api_dir, count = 3, focus = false })
      assert.equals("3", counted.name)
      assert.equals(api_dir, counted.cwd)
    end)

    it("from outside the project the terminal still belongs to the folder's project", function()
      vim.cmd("cd " .. vim.fn.fnameescape(base))
      local h = terminal.open({ dir = docs, focus = false })
      assert.equals("docs/", h.name)
      assert.equals(0, #terminal.list(), "not a terminal of the directory the editor is in")
      assert.same({ "docs/" }, names(true))
      vim.cmd("cd " .. vim.fn.fnameescape(project))
      assert.same({ "docs/" }, names())
    end)

    it(
      "toggle creates the folder's terminal, then hides it; hide and close find it by the folder",
      function()
        assert.is_true(terminal.toggle({ dir = docs }))
        local h = terminal.list()[1]
        assert.equals("docs/", h.name)
        assert.equals(1, #vim.fn.win_findbuf(h.bufnr))
        jobs.settle()
        assert.is_true(terminal.toggle({ dir = docs })) -- focused -> hide
        assert.equals(0, #vim.fn.win_findbuf(h.bufnr))
        jobs.settle()
        assert.is_true(terminal.toggle({ dir = docs })) -- hidden -> show
        assert.equals(1, #vim.fn.win_findbuf(h.bufnr))
        jobs.settle()
        assert.is_true(terminal.hide({ dir = docs }))
        jobs.settle()
        assert.is_true(terminal.close({ dir = docs }))
        assert.equals(0, #terminal.list(true))
      end
    )

    it("what is not a directory is refused with a reason and starts nothing", function()
      local cases = {
        { base .. "/nope", "target.dir is not a directory" },
        { docs .. "/guide.md", "target.dir is not a directory" },
        { "", "target.dir must be a non-empty string" },
        { 3, "target.dir must be a non-empty string" },
      }
      for _, case in ipairs(cases) do
        local target = { dir = case[1] }
        local handle, err = terminal.open(target)
        assert.is_nil(handle, vim.inspect(target))
        assert.truthy(err:find(case[2], 1, true), vim.inspect(target) .. ": " .. tostring(err))
        local ok, terr = terminal.toggle(target)
        assert.is_false(ok)
        assert.equals(err, terr)
        local sent, serr = terminal.send("ls", target)
        assert.is_false(sent)
        assert.equals(err, serr)
        local ran, rerr = terminal.run({ "ls" }, target)
        assert.is_false(ran)
        assert.equals(err, rerr)
        local closed, cerr = terminal.close(target)
        assert.is_false(closed)
        assert.equals(err, cerr)
      end
      assert.equals(0, #terminal.list(true), "no terminal in the cwd instead")
      vim.wait(100, function()
        return false
      end)
      local shown = false
      for _, n in ipairs(notices) do
        if n.msg:find("target.dir is not a directory: " .. base .. "/nope", 1, true) then
          shown = true
        end
      end
      assert.is_true(shown, "the user is told which directory it was")
    end)

    it("run types its line into the folder's terminal, not into the run terminal", function()
      local ok, err
      local sent = jobs.record_sends(function()
        ok, err = terminal.run({ "echo", "x" }, { dir = docs })
      end)
      assert.is_true(ok, err)
      assert.same({ "docs/" }, names())
      local h = terminal.list()[1]
      assert.equals(docs, h.cwd)
      assert.equals(h.job, sent[1].job)
      assert.equals("echo x" .. (vim.fn.has("win32") == 1 and "\r" or "\n"), sent[1].text)
    end)

    it("send and run with the project root as the directory use the run terminal", function()
      jobs.record_sends(function()
        assert.is_true(terminal.send("x", { dir = project }))
        assert.is_true(terminal.run("y", { dir = project, count = 0 }))
      end)
      assert.same({ "run" }, names())
    end)

    it("run with direct starts the job in the folder; an explicit cwd wins", function()
      local ok, err, h = terminal.run(jobs.sleeper(), { direct = true, dir = docs, focus = false })
      assert.is_true(ok, err)
      assert.equals("docs/", h.name)
      assert.equals(docs, h.cwd)
      local _, _, other = terminal.run(
        jobs.sleeper(),
        { direct = true, dir = docs, name = "other", cwd = api_dir, focus = false }
      )
      assert.equals(api_dir, other.cwd)
    end)
  end)

  it("list(true) shows every project, list() only the current one", function()
    terminal.open({ name = "a", focus = false })
    assert.equals(1, #terminal.list())
    assert.equals(1, #terminal.list(true))
  end)
end)
