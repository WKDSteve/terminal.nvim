-- Inside tmux, the status of this Neovim (mode, file, branch, ...) goes into the pane's options through a real `tmux`
-- process per change (terminal.status.exporters.tmux). `tmux` is a recording stand-in on the PATH: which options would
-- be set is checked, that the status line of real tmux shows them is a person's check.
return {
  id = "terminal.status-tmux",
  feature = "terminal.status-export",
  title = "terminal.nvim: inside tmux a mode change and a new file start `tmux set-option -p` on this pane",
  task = "terminal.nvim/performance-pruefung-luecken-schliessen-katalog-feature-shee",
  fakes = { "tmux" },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
      -- Neovim runs in tmux pane %7 (and not inside another Neovim's terminal).
      vim.env.TMUX = "/tmp/tmux-1000/default,1,0"
      vim.env.TMUX_PANE = "%7"
      vim.env.NVIM = nil
      _G.setup()
      ---How many publishes went to the pane so far.
      _G.publishes = function()
        local n = 0
        for _, call in ipairs(_G.fake_calls("tmux")) do
          if call.argv[1] == "set-option" and call.argv[2] == "-p" and call.argv[4] == "%7" then
            n = n + 1
          end
        end
        return n
      end]],
    },

    {
      wait = [[_G.fake_called("tmux", { "set-option", "-p", "-t", "%7", "@terminal_branch" })]],
      timeout = 5000,
      note = "the first status is published to this pane at start",
    },
    { lua = [[_G.before = _G.publishes()]] },
    { keys = ":edit status-a.txt<CR>", note = "another file" },
    { input = "i", note = "insert mode" },
    {
      wait = [[_G.publishes() > _G.before]],
      timeout = 5000,
      note = "the change starts tmux again (debounced)",
    },
    { input = "<Esc>" },
    { lua = [[_G.settled = _G.publishes()]] },
    { settle = 300 },
    { keys = ":echo 1<CR>", note = "nothing the pane shows changed" },
    { settle = 300 },
    {
      expect = [[_G.publishes() <= _G.settled + 1]],
      note = "no tmux process for a change the options do not carry",
    },
  },
  manual = {
    "Inside real tmux with a status line that shows #{@terminal_mode}: the mode follows Neovim's",
  },
}
