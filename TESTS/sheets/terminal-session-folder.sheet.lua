-- Live check: the real sessions.nvim saves a session with a terminal opened for a folder. Loaded again, the
-- terminal comes back under its name in that folder; with the folder deleted, it comes back in the project's
-- directory and a warning names it.
return {
  id = "terminal.session-folder",
  feature = "terminal.sessions",
  title = "terminal.nvim: a session brings a folder's terminal back in its folder, or in the project when it is gone",
  task = "terminal.nvim/live-check",
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
        autosave = false,
        autoload = false,
        save_last = false,
      })
      _G.setup()
      _G.PROJ = _G.DIR .. "/proj"
      vim.fn.mkdir(_G.PROJ .. "/.git", "p")
      vim.fn.mkdir(_G.PROJ .. "/docs", "p")
      vim.cmd.cd(vim.fn.fnameescape(_G.PROJ))
      vim.cmd.edit("notes.txt")
      _G.close_all = function()
        for _, h in ipairs(require("terminal").list()) do
          require("terminal").close({ name = h.name })
        end
      end]],
    },

    {
      keys = ":Terminal open --dir=docs --layout=split<CR>",
      note = "a terminal for the folder docs/",
    },
    { wait = [[_G.ready("docs/")]], timeout = 8000 },
    { input = "<C-\\><C-n>:Terminal hide docs/<CR>" },
    { wait = [[_G.win_of("docs/") == nil]] },
    { keys = ":Session save work<CR>" },
    { wait = [[vim.fn.filereadable(_G.DIR .. "/sessions/.work.terminals.json") == 1]] },

    { lua = [[_G.close_all()]], note = "the terminals closed" },
    { wait = [[_G.names() == ""]] },
    { keys = ":Session load work<CR>" },
    { wait = [[_G.term("docs/") ~= nil]], timeout = 8000 },
    {
      expect = [[vim.uv.fs_realpath(_G.term("docs/").cwd) == vim.uv.fs_realpath(_G.PROJ .. "/docs")]],
      note = "back under its name, in docs/ (real paths: macOS's temp directory is a symlink)",
    },
    { expect = [[_G.win_of("docs/") == nil]], note = "and hidden" },

    {
      lua = [[_G.close_all()
      vim.fn.delete(_G.PROJ .. "/docs", "rf")]],
      note = "the terminals closed, the folder docs/ deleted",
    },
    { wait = [[_G.names() == ""]] },
    { keys = ":Session load work<CR>" },
    { wait = [[_G.term("docs/") ~= nil]], timeout = 8000 },
    {
      expect = [[vim.uv.fs_realpath(_G.term("docs/").cwd) == vim.uv.fs_realpath(_G.PROJ)]],
      note = "under its name, in the project's directory",
    },
    {
      expect = [[_G.noted("reopened in the project's directory")]],
      note = "and a warning says so",
    },
  },
  manual = {
    "Neovim started in the project with sessions.nvim's autoload: a terminal opened with :Terminal open --dir=<folder> (or Terminal here in the tree) is back in that folder, toggle shows it",
    "The same with the folder deleted before the start: the terminal is in the project's directory and the warning is readable, not lost behind the start screen",
  },
}
