-- Bindings checklist: :Terminal list, the kit picker of lib.nvim over this project's terminals.
return {
  id = "terminal.list",
  feature = "terminal.list",
  title = "terminal.nvim: :Terminal list opens, closes and sends a line",
  task = "terminal.nvim/live-check",
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
      _G.setup()
      _G.prompt = function()
        return vim.bo.filetype == "lib-kit-picker-prompt"
      end]],
    },

    { keys = ":Terminal list<CR>", note = "no terminal yet: it says so" },
    { wait = [[_G.noted("no terminals in this project")]] },

    { keys = ":Terminal open alpha --layout=split<CR>" },
    { wait = [[_G.ready("alpha")]], timeout = 8000 },
    { input = "<C-\\><C-n>:Terminal hide alpha<CR>" },
    { wait = [[_G.win_of("alpha") == nil]] },
    { keys = ":Terminal open beta --layout=split<CR>" },
    { wait = [[_G.ready("beta")]], timeout = 8000 },
    { input = "<C-\\><C-n>:Terminal hide beta<CR>" },
    { wait = [[_G.win_of("beta") == nil]] },

    { input = ":Terminal list<CR>", note = "the picker opens" },
    { wait = [[_G.prompt()]] },
    { input = "alpha", note = "typed words filter" },
    { wait = [[vim.api.nvim_get_current_line():find("alpha", 1, true) ~= nil]] },
    { lua = [[vim.wait(200)]], note = "the prompt debounces its filter" },
    { input = "<CR>", note = "<CR> opens the row" },
    {
      wait = [[_G.win_of("alpha") ~= nil and vim.api.nvim_get_current_win() == _G.win_of("alpha")]],
    },
    { input = "<C-\\><C-n>:Terminal hide alpha<CR>" },
    { wait = [[_G.win_of("alpha") == nil]] },

    { input = ":Terminal list<CR>" },
    { wait = [[_G.prompt()]] },
    { input = "beta" },
    { wait = [[vim.api.nvim_get_current_line():find("beta", 1, true) ~= nil]] },
    { lua = [[vim.wait(200)]] },
    {
      lua = [[vim.ui.input = function(opts, on_confirm)
        _G.ASKED = opts.prompt
        on_confirm("echo picked>list.txt")
      end]],
      note = "the answer to the prompt: input() does not wait in the headless child (seen 2026-11-07)",
    },
    { input = "<C-s>", note = "<C-s> asks for a line, the list closes" },
    { wait = [[_G.ASKED ~= nil and _G.ASKED:find("beta", 1, true) ~= nil and not _G.prompt()]] },
    {
      wait = [[_G.wrote("list.txt", "picked")]],
      timeout = 8000,
      note = "it runs in that terminal",
    },

    { input = ":Terminal list<CR>" },
    { wait = [[_G.prompt()]] },
    { input = "alpha" },
    { wait = [[vim.api.nvim_get_current_line():find("alpha", 1, true) ~= nil]] },
    { lua = [[vim.wait(200)]] },
    { input = "<C-x>", note = "<C-x> closes the row, the list stays open" },
    { wait = [[_G.names() == "beta"]] },
    { expect = [[_G.prompt()]] },
  },
  manual = {
    "In a real session: <C-s> in :Terminal list shows the prompt, what is typed there runs in that terminal",
  },
}
