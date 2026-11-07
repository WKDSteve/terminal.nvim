-- Bindings checklist: <C-h>, <C-j>, <C-k>, <C-l> as the owner's config binds them (nav_*: normal mode, with a count, and
-- the hand-off at the edge), and the terminal-mode defaults. The hand-off command goes to a recorder: that a real
-- multiplexer moves its focus is a person's check.
return {
  id = "terminal.navigate",
  title = "terminal.nvim: <C-h/j/k/l> move between windows, take a count and hand off at the edge",
  task = "terminal.nvim/live-check",
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
      _G.setup({
        keymaps = {
          nav_left = "<C-h>", nav_down = "<C-j>", nav_up = "<C-k>", nav_right = "<C-l>", window_right = "<C-l>",
        },
      })
      -- The hand-off goes to a recorder, as if Neovim ran inside tmux.
      _G.HANDOFF = {}
      require("terminal.navigate").setup(require("terminal.config").get_all(), { TMUX = "x" }, function(argv)
        _G.HANDOFF[#_G.HANDOFF + 1] = table.concat(argv, " ")
      end)
      _G.handed = function(word)
        return table.concat(_G.HANDOFF, "\n"):find(word, 1, true) ~= nil
      end
      -- Three windows in a row, two below each other in the middle one.
      _G.a = vim.api.nvim_get_current_win()
      vim.cmd("rightbelow vsplit")
      _G.b = vim.api.nvim_get_current_win()
      vim.cmd("rightbelow vsplit")
      _G.c = vim.api.nvim_get_current_win()
      vim.api.nvim_set_current_win(_G.b)
      vim.cmd("rightbelow split")
      _G.d = vim.api.nvim_get_current_win()
      _G.at = function(win)
        return vim.api.nvim_get_current_win() == win
      end]],
    },

    { keys = "<C-k>", note = "up, from d to b" },
    { expect = [[_G.at(_G.b) and #_G.HANDOFF == 0]] },
    { keys = "<C-j>", note = "down, from b to d" },
    { expect = [[_G.at(_G.d) and #_G.HANDOFF == 0]] },
    { keys = "<C-l>", note = "right, from d to c" },
    { expect = [[_G.at(_G.c) and #_G.HANDOFF == 0]] },
    { keys = "<C-h>", note = "left, back into the middle" },
    { expect = [[_G.at(_G.d) or _G.at(_G.b)]] },
    { keys = "<C-h>", note = "left, to a" },
    { expect = [[_G.at(_G.a) and #_G.HANDOFF == 0]] },

    { keys = "2<C-l>", note = "a count moves two windows" },
    { expect = [[_G.at(_G.c) and #_G.HANDOFF == 0]] },
    { keys = "2<C-h>", note = "and two back" },
    { expect = [[_G.at(_G.a)]] },

    { keys = "<C-h>", note = "at the left edge: tmux is asked, for the pane on the left" },
    { expect = [[_G.at(_G.a) and _G.handed("#{pane_at_left}") and _G.handed("select-pane -L")]] },
    { lua = [[vim.api.nvim_set_current_win(_G.c); _G.HANDOFF = {}]] },
    { keys = "<C-l>", note = "at the right edge" },
    { expect = [[_G.at(_G.c) and _G.handed("#{pane_at_right}") and _G.handed("select-pane -R")]] },
    { lua = [[_G.HANDOFF = {}]] },
    { keys = "<C-k>", note = "at the top edge" },
    { expect = [[_G.at(_G.c) and _G.handed("#{pane_at_top}") and _G.handed("select-pane -U")]] },
    { lua = [[_G.HANDOFF = {}]] },
    { keys = "<C-j>", note = "at the bottom edge" },
    { expect = [[_G.at(_G.c) and _G.handed("#{pane_at_bottom}") and _G.handed("select-pane -D")]] },
    { lua = [[_G.HANDOFF = {}]] },

    { keys = ":Terminal open nav --layout=split<CR>", note = "from terminal mode the same keys" },
    { wait = [[_G.ready("nav") and vim.api.nvim_get_mode().mode == "t"]], timeout = 8000 },
    { lua = [[_G.nav = vim.api.nvim_get_current_win()]] },
    { input = "<C-k>" },
    {
      wait = [[not _G.at(_G.nav) and vim.api.nvim_get_mode().mode == "n"]],
      note = "up, out of terminal mode",
    },
    { lua = [[vim.api.nvim_set_current_win(_G.nav); _G.HANDOFF = {}]] },
    { input = "i" },
    { wait = [[vim.api.nvim_get_mode().mode == "t"]] },
    { input = "<C-j>" },
    {
      wait = [[_G.handed("select-pane -D")]],
      note = "the bottom edge hands off from terminal mode too",
    },
    { lua = [[vim.api.nvim_set_current_win(_G.nav); _G.HANDOFF = {}]] },
    { input = "i" },
    { wait = [[vim.api.nvim_get_mode().mode == "t"]] },
    { input = "<C-h>" },
    {
      wait = [[_G.handed("select-pane -L")]],
      note = "the left edge too: this split spans the whole width",
    },
    { expect = [[vim.api.nvim_get_mode().mode ~= "t"]], note = "and terminal mode is left" },
    { lua = [[vim.api.nvim_set_current_win(_G.nav); _G.HANDOFF = {}]] },
    { input = "i" },
    { wait = [[vim.api.nvim_get_mode().mode == "t"]] },
    { input = "<C-l>" },
    {
      wait = [[_G.handed("select-pane -R")]],
      note = "window_right, once bound, at the right edge",
    },
  },
  manual = {
    "Inside real tmux and real WezTerm: <C-h/j/k/l> at Neovim's edge moves the focus into the neighbouring pane",
  },
}
