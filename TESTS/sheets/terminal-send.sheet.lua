-- Bindings checklist: :Terminal send line|selection|file and :Terminal run, typed into a real shell. A line that runs is
-- proved by the file it writes into the temp directory of the terminal (the same words in `sh` and `cmd.exe`).
return {
  id = "terminal.send",
  title = "terminal.nvim: :Terminal send line, selection, file and :Terminal run",
  task = "terminal.nvim/testblatt-bindings-checkliste",
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
      _G.setup()
      _G.home = vim.api.nvim_get_current_win()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, {
        "echo typed-only",
        "echo ran>line.txt",
        "pick echo inner>sel.txt end",
        "first row",
        "second row",
      })
      vim.api.nvim_win_set_cursor(0, { 1, 0 })]],
    },

    { keys = ":Terminal send line<CR>", note = "typed into the run terminal, created on the way" },
    { wait = [[_G.ready("run")]], timeout = 8000 },
    { wait = [[_G.shows("run", "echo typed-only")]], timeout = 8000, note = "it arrives" },
    { lua = [[vim.wait(300)]], note = "time to run, if it did" },
    {
      expect = [[not _G.shows("run", "typed-only", 2)]],
      note = "without --exec nothing ran: the word is on the screen once, as typed",
    },
    {
      expect = [[vim.api.nvim_get_current_win() == _G.home]],
      note = "the focus stays in the buffer",
    },

    { lua = [[vim.api.nvim_win_set_cursor(0, { 2, 0 })]] },
    { keys = ":Terminal send line --exec<CR>", note = "--exec presses Enter" },
    { wait = [[_G.wrote("line.txt", "ran")]], timeout = 8000 },

    { lua = [[vim.api.nvim_win_set_cursor(0, { 3, 5 })]] },
    {
      keys = "v17l:Terminal send selection other --exec<CR>",
      note = "the characters of the selection, to a named terminal",
    },
    { wait = [[_G.wrote("sel.txt", "inner")]], timeout = 8000 },
    {
      expect = [[_G.term("other") ~= nil and not _G.shows("other", "pick") and not _G.shows("other", " end")]],
    },

    {
      keys = ":4,5Terminal send selection other<CR>",
      note = "two lines without --exec would run one by one",
    },
    { wait = [[_G.noted("2 lines would be executed one by one")]] },
    { expect = [[not _G.shows("other", "first row")]], note = "nothing was sent" },

    {
      keys = ":Terminal send file other<CR>",
      note = "the whole file without --exec is refused the same way",
    },
    { wait = [[_G.noted("5 lines would be executed one by one")]] },
    {
      lua = [[vim.cmd.edit("single.txt")
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "echo whole>file.txt" })]],
    },
    { keys = ":Terminal send file other --exec<CR>", note = "a file of one line, run" },
    { wait = [[_G.wrote("file.txt", "whole")]], timeout = 8000 },

    {
      lua = [[vim.api.nvim_buf_set_lines(0, 0, -1, false, { "echo one>many1.txt", "echo two>many2.txt" })]],
    },
    {
      keys = ":Terminal send file other --exec<CR>",
      note = "several lines with --exec: each one runs",
    },
    { wait = [[_G.wrote("many1.txt", "one") and _G.wrote("many2.txt", "two")]], timeout = 8000 },

    { lua = [[vim.api.nvim_set_current_win(_G.home)]] },
    {
      keys = ":Terminal run echo typed>run.txt<CR>",
      note = "run types the line into the run terminal and runs it",
    },
    { wait = [[_G.wrote("run.txt", "typed")]], timeout = 8000 },
    { keys = ":Terminal run<CR>", note = "no command" },
    { wait = [[_G.noted("run: no command given")]] },

    {
      lua = [[vim.cmd("Terminal run --direct --name=job -- "
        .. vim.fn.fnameescape(vim.fs.normalize(vim.v.progpath))
        .. " --version")]],
      note = "--direct: the program is the job, no shell; the words after -- stay its own",
    },
    { wait = [[_G.term_any("job") ~= nil]] },
    {
      wait = [[_G.shows("job", "NVIM v")]],
      timeout = 8000,
      note = "its output is on the screen",
    },
    { wait = [[_G.term_any("job").exited == true]], timeout = 8000, note = "it ended" },
    {
      expect = [[vim.fn.bufwinid(_G.term_any("job").bufnr) ~= -1]],
      note = "the window stays after it ended",
    },
  },
}
