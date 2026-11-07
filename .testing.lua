-- .testing.lua -- configuration of testing.nvim for this project.
-- Every key is optional; the keys are documented in testing.nvim's docs/CONFIG.md. Loading this
-- file executes it (same trust as running the specs).
return {
  -- Lua module root of the project.
  plugin = "terminal",
  -- How the spec files are run: "auto" = sniffed per file.
  dialect = "auto",
  -- Dependencies (directory names) put on the runtimepath.
  deps = { "lib.nvim" },
  -- One nvim per spec file: nothing leaks from one file into the next (terminal jobs, windows).
  isolated = "file",
  host = "c",
  -- The worktree of `ci commit` has no sibling checkouts: the child editors of the sheets find them this way.
  env_allow = { "LIB_NVIM_DIR", "TESTING_NVIM_DIR" },
  -- A case without assertions fails: a spec that asserts nothing proves nothing.
  assertions = "error",
  -- Real shells are started by some specs (a PowerShell property run takes 5-10 s on a machine
  -- that is busy with something else); the default of 10 s per case cut them off.
  -- All test sheets run in one spec file, one child editor each: the defaults are reached under load there too
  -- (fileops, 2026-11-07).
  timeouts = { case_ms = 30000, file_ms = 300000 },
  guards = {
    fs = "error",
    scheduled_error = "error",
    prompt = "error",
    deprecation = "error",
    -- The native backend starts real shell jobs in specs that exercise it, so process_net stays
    -- at its default; specs for the pure core never start one.
  },
  guard_allow = {
    -- sheets_spec.lua: every test sheet (TESTS/sheets/) runs in a child editor.
    spawn = { "nvim" },
  },
  -- gated: a failed conformance check makes `scripts/test.sh conformance` exit 1 (docs/CONFORMANCE.md of testing.nvim)
  conformance = {
    gate = true,
    waivers = {
      {
        check = "K12",
        rule = "REL-22",
        text = "terminal.window_",
        level = "warn",
        expires = "2027-04-14",
        reason = "terminal-mode window navigation keys that hand off to the multiplexer at the edge; the `:Terminal` command is about terminals, window motion is the user's own :wincmd",
      },
      {
        check = "K13",
        rule = "UI-22",
        text = "terminal.window_down",
        level = "warn",
        expires = "2027-04-14",
        reason = "<C-j> completes the <C-h>/<C-j>/<C-k> window navigation set in terminal mode; deliberate and configurable (window_down)",
      },
    },
  },
}
