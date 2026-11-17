-- Live check: the real sessions.nvim with `relative_paths` saves a session with a terminal opened for a
-- folder; the same project checked out at another place loads it, and the terminal comes back in that
-- folder of the new place, not in the old one (which still exists and is another project now).
return {
  id = "terminal.session-moved",
  feature = "terminal.sessions",
  title = "terminal.nvim: a session's terminal follows the project to its new place",
  task = "terminal.nvim/terminal-sidecar-follows-sessions-nvim-s-relative-paths-root",
  requires = {
    {
      lua = [[vim.g.terminal_sheets_sessions_nvim ~= nil]],
      reason = "sessions.nvim was not found (TESTS/minimal_init.lua, vim.g.terminal_sheets_sessions_nvim)",
    },
  },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
      vim.opt.rtp:append(vim.g.terminal_sheets_sessions_nvim)
      require("sessions").setup({
        root = _G.DIR .. "/sessions",
        relative_paths = true,
        autosave = false,
        autoload = false,
        save_last = false,
      })
      _G.setup()
      _G.OLD = _G.DIR .. "/old"
      _G.NEW = _G.DIR .. "/new"
      for _, p in ipairs({ _G.OLD, _G.NEW }) do
        vim.fn.mkdir(p .. "/.git", "p")
        vim.fn.mkdir(p .. "/docs", "p")
      end
      vim.cmd.cd(vim.fn.fnameescape(_G.OLD))
      vim.cmd.edit("notes.txt")]],
    },

    {
      keys = ":Terminal open --dir=docs --layout=split<CR>",
      note = "a terminal for the folder docs/",
    },
    { wait = [[_G.ready("docs/")]], timeout = 8000 },
    { input = "<C-\\><C-n>:Terminal hide docs/<CR>" },
    { wait = [[_G.win_of("docs/") == nil]] },

    {
      keys = ":Session save work<CR>",
      note = "the sidecar stores docs/ relative to the session root",
    },
    {
      wait = [[(function()
        local f = io.open(_G.DIR .. "/sessions/.work.terminals.json")
        local text = f and f:read("*a") or ""
        if f then f:close() end
        local ok, decoded = pcall(vim.json.decode, text)
        return ok and decoded.terminals[1].cwd == "{{SESSION_ROOT}}/docs"
      end)()]],
    },

    {
      lua = [[for _, h in ipairs(require("terminal").list()) do
        require("terminal").close({ name = h.name })
      end
      vim.cmd.cd(vim.fn.fnameescape(_G.NEW))]],
      note = "the terminals closed, the editor in the same project at another place",
    },
    { wait = [[_G.names() == ""]] },

    { keys = ":Session load work<CR>" },
    { wait = [[_G.term("docs/") ~= nil]], timeout = 8000 },
    {
      expect = [[vim.uv.fs_realpath(_G.term("docs/").cwd) == vim.uv.fs_realpath(_G.NEW .. "/docs")]],
      note = "back in docs/ of the new place (real paths: macOS's temp directory is a symlink)",
    },
    { expect = [[not _G.noted("reopened in the project's directory")]], note = "and not moved" },
  },
  manual = {
    "On a second machine with another path: :Session load brings a folder terminal back in that folder",
  },
}
