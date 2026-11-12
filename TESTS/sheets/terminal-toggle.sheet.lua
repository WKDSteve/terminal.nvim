-- Bindings checklist: <A-h>, <Esc>, :Terminal, :Terminal toggle|open|hide|close with a real shell.
return {
  id = "terminal.toggle",
  feature = "terminal.toggle",
  title = "terminal.nvim: <A-h>, <Esc> and :Terminal toggle, open, hide, close",
  task = "terminal.nvim/testblatt-bindings-checkliste",
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
      _G.setup()
      _G.home = vim.api.nvim_get_current_win()]],
    },

    { keys = "<A-h>", note = "the toggle key creates the default terminal" },
    { wait = [[_G.ready("main")]], timeout = 8000 },
    { expect = [[_G.names() == "main" and _G.in_float() and vim.bo.buftype == "terminal"]] },
    { wait = [[vim.api.nvim_get_mode().mode == "t"]], note = "it starts in terminal mode" },
    { input = "<Esc>", note = "<Esc> leaves terminal mode" },
    { wait = [[vim.api.nvim_get_mode().mode == "nt"]] },

    { input = "<A-h>", note = "focused: the key hides it, the job keeps running" },
    { wait = [[_G.win_of("main") == nil]] },
    { expect = [[_G.term("main") ~= nil and vim.fn.jobwait({ _G.term("main").job }, 0)[1] == -1]] },
    {
      expect = [[vim.api.nvim_get_current_win() == _G.home]],
      note = "back in the window it came from",
    },

    { keys = ":Terminal<CR>", note = "the bare command toggles the default terminal" },
    { wait = [[_G.win_of("main") ~= nil]] },
    { input = "<C-\\><C-n>:Terminal toggle main<CR>", note = "the toggle route hides it" },
    { wait = [[_G.win_of("main") == nil]] },

    { keys = "3<A-h>", note = "a count picks terminal 3" },
    { wait = [[_G.names() == "3,main" and _G.win_of("3") ~= nil]] },
    { input = "<C-\\><C-n>:Terminal toggle 3<CR>", note = 'the name "3" is that same terminal' },
    { wait = [[_G.win_of("3") == nil and _G.names() == "3,main"]] },

    { keys = ":Terminal open work --layout=split<CR>", note = "open creates it, as a split" },
    { wait = [[_G.win_of("work") ~= nil]] },
    { expect = [[not _G.in_float() and vim.api.nvim_get_current_win() == _G.win_of("work")]] },
    { input = "<C-\\><C-n><C-w>p" },
    { wait = [[vim.api.nvim_get_current_win() ~= _G.win_of("work")]] },
    {
      keys = ":Terminal open work<CR>",
      note = "open on a visible one focuses it, makes no second one",
    },
    {
      wait = [[vim.api.nvim_get_current_win() == _G.win_of("work") and _G.names() == "3,main,work"]],
    },

    {
      input = "<C-\\><C-n>:Terminal hide work<CR>",
      note = "hide closes the window, the job stays",
    },
    { wait = [[_G.win_of("work") == nil and _G.term("work") ~= nil]] },
    { keys = ":Terminal hide nope<CR>", note = "hide of an unknown name says so" },
    { wait = [[_G.noted("no terminal 'nope' in this project")]] },

    {
      lua = [[vim.wait(500)]],
      note = "a pty closed right after a resize can take Neovim down on Windows (TESTS/support/jobs.lua)",
    },
    { keys = ":Terminal close work<CR>", note = "close stops the job and forgets it" },
    { wait = [[_G.names() == "3,main"]] },
    { keys = ":Terminal close nope<CR>", note = "close of an unknown name says so" },
    { expect = [[_G.noted("no terminal 'nope' in this project")]] },

    { keys = ":Terminal open t --layout=tab<CR>", note = "the tab layout" },
    { wait = [[vim.fn.tabpagenr("$") == 2 and _G.win_of("t") ~= nil]] },
    { input = "<C-\\><C-n>:tabprevious<CR>" },
    { wait = [[vim.fn.tabpagenr() == 1]] },
    { keys = ":Terminal open v --layout=vsplit<CR>", note = "the vsplit layout" },
    { wait = [[_G.win_of("v") ~= nil and vim.fn.winlayout()[1] == "row"]] },
  },
}
