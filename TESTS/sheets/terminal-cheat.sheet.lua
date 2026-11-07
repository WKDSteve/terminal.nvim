-- Bindings checklist: :Terminal cheat, the float of the shell cheatsheet.
return {
  id = "terminal.cheat",
  title = "terminal.nvim: :Terminal cheat pages, closes and types the line",
  task = "terminal.nvim/testblatt-bindings-checkliste",
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
      _G.setup()
      _G.home = vim.api.nvim_get_current_win()
      _G.page = function()
        return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
      end]],
    },

    { keys = ":Terminal cheat bash<CR>", note = "the sheet that is named" },
    { expect = [[_G.in_float() and _G.page() ~= ""]] },
    { lua = [[_G.first = _G.page()]] },
    { keys = "]]", note = "the next section" },
    { expect = [[_G.page() ~= _G.first]] },
    { keys = "[[", note = "and back" },
    { expect = [[_G.page() == _G.first]] },
    { keys = "q", note = "q closes" },
    { expect = [[not _G.in_float() and vim.api.nvim_get_current_win() == _G.home]] },
    { keys = ":Terminal cheat<CR>", note = "without a name: the sheet of the configured shell" },
    { expect = [[_G.in_float() and _G.page() ~= ""]] },
    { keys = ":Terminal cheat<CR>", note = "called again, it closes" },
    { expect = [[not _G.in_float()]] },

    {
      keys = ":Terminal cheat nosuchshell<CR>",
      note = "an unknown name falls back to the common sheet",
    },
    { expect = [[_G.in_float() and _G.page() ~= ""]] },
    { keys = "q" },

    { keys = ":Terminal cheat bash<CR>" },
    {
      lua = [[_G.QUERY = "pipefail"
      vim.ui.input = function(_, on_confirm)
        on_confirm(_G.QUERY)
      end]],
      note = "the answer to the search prompt: input() does not wait in the headless child",
    },
    { keys = "/", note = "the search goes over all sections" },
    { expect = [[vim.api.nvim_get_current_line():find("pipefail", 1, true) ~= nil]] },
    { lua = [[_G.QUERY = "no-such-word-anywhere"]] },
    { keys = "/" },
    { wait = [[_G.noted("nothing matches 'no-such-word-anywhere'")]] },
    { keys = "q" },

    {
      lua = [[vim.cmd("Terminal open main --layout=split")
      vim.cmd("stopinsert")]],
      note = "from a terminal window: the line goes to that terminal",
    },
    { wait = [[_G.ready("main")]], timeout = 8000 },
    { keys = ":Terminal cheat bash<CR>" },
    { keys = "]]", note = "past the introduction" },
    {
      lua = [[local parse = require("terminal.cheatsheet.parse")
      for i, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
        if parse.command_of(line) then
          _G.command = parse.command_of(line)
          vim.api.nvim_win_set_cursor(0, { i, 0 })
          break
        end
      end
      assert(_G.command, "a section without a command")]],
      note = "the first line of the page that holds a command",
    },
    { keys = "<CR>", note = "<CR> types it into the terminal" },
    { expect = [[not _G.in_float()]] },
    { lua = [[_G.typed = vim.trim(_G.command):sub(1, 12)]] },
    { wait = [[_G.shows("main", _G.typed)]], timeout = 8000 },
  },
}
