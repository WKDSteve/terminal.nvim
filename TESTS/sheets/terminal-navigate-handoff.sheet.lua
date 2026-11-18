-- Inside tmux, <C-h/j/k/l> at Neovim's edge start a real `tmux` process (detached, through terminal.core.exec).
-- `tmux` is a recording stand-in on the PATH: what the plugin starts is checked, that real tmux moves its focus is a
-- person's check (terminal-navigate.sheet.lua drives the window motion through an in-memory recorder).
return {
  id = "terminal.navigate-handoff",
  feature = "terminal.navigate",
  title = "terminal.nvim: inside tmux the edge keys start `tmux select-pane`, from normal and terminal mode",
  task = "terminal.nvim/performance-pruefung-luecken-schliessen-katalog-feature-shee",
  fakes = { "tmux" },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
      -- Neovim runs in a tmux pane: the hand-off reads the environment when it is set up.
      vim.env.TMUX = "/tmp/tmux-1000/default,1,0"
      vim.env.TMUX_PANE = "%7"
      _G.setup({ keymaps = { nav_left = "<C-h>", nav_right = "<C-l>", window_right = "<C-l>" } })]],
    },

    {
      keys = "<C-l>",
      note = "one window: the right edge, tmux is asked for the pane on the right",
    },
    {
      wait = [[_G.fake_called("tmux", { "if-shell", "-F", "#{pane_at_right}" })]],
      timeout = 5000,
      note = "a real process was started for it",
    },
    { expect = [[#vim.api.nvim_list_wins() == 1]], note = "Neovim's own windows stay as they are" },

    { keys = ":Terminal open nav --layout=split<CR>", note = "a terminal below" },
    { wait = [[_G.ready("nav") and vim.api.nvim_get_mode().mode == "t"]], timeout = 8000 },
    { input = "<C-h>", note = "the left edge from terminal mode" },
    {
      wait = [[_G.fake_called("tmux", { "if-shell", "-F", "#{pane_at_left}" })]],
      timeout = 5000,
    },
    { wait = [[vim.api.nvim_get_mode().mode ~= "t"]], note = "and terminal mode is left" },
  },
  manual = {
    "Inside real tmux: <C-l> at Neovim's right edge moves the focus into the pane on the right",
  },
}
