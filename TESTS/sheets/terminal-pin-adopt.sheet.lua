-- Bindings checklist: :Terminal pin and :Terminal adopt. No multiplexer runs here: the refusal without one is real, the
-- rest goes through the fake `wezterm cli` of TESTS/support/fakes.lua. A real pane is a person's check.
return {
  id = "terminal.pin-adopt",
  title = "terminal.nvim: :Terminal pin and :Terminal adopt, against a fake multiplexer",
  task = "terminal.nvim/live-check",
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
      _G.setup()
      _G.home = vim.api.nvim_get_current_win()
      _G.terminal_buffers = function()
        return #vim.tbl_filter(function(b)
          return vim.bo[b].buftype == "terminal"
        end, vim.api.nvim_list_bufs())
      end]],
    },

    { keys = ":Terminal pin nope<CR>", note = "no such terminal" },
    { wait = [[_G.noted("pin: no terminal 'nope' in this project")]] },
    { keys = ":Terminal adopt nope<CR>", note = "no such terminal" },
    { wait = [[_G.noted("adopt: no terminal 'nope' in this project")]] },

    { keys = ":Terminal open work --layout=split<CR>" },
    { wait = [[_G.ready("work")]], timeout = 8000 },
    { input = "<C-\\><C-n><C-w>p" },
    { wait = [[vim.api.nvim_get_current_win() == _G.home]] },
    { keys = ":Terminal adopt work<CR>", note = "a native terminal has no pane to show" },
    { wait = [[_G.noted("lives in native, which has no pane to show")]] },
    { keys = ":Terminal pin work<CR>", note = "outside a multiplexer the terminal stays as it is" },
    { wait = [[_G.noted("no multiplexer backend is available")]] },
    { expect = [[_G.term("work").backend == "native"]] },

    {
      lua = [[_G.fake_multiplexer("hello from the pane\nsecond line\n")
      _G.setup()]],
      note = "setup again: the plugin remembers until then that WezTerm is not there",
    },
    {
      lua = [[vim.wait(500)]],
      note = "a pty closed right after a resize can take Neovim down on Windows",
    },
    {
      keys = ":Terminal pin work --backend=wezterm --layout=split<CR>",
      note = "restarted as a pane",
    },
    { wait = [[_G.term("work") ~= nil and _G.term("work").backend == "wezterm"]], timeout = 5000 },
    { expect = [[_G.mux_called("split-pane") and _G.names() == "work"]] },
    { expect = [[_G.terminal_buffers() == 0]], note = "the native terminal is gone" },
    { keys = ":Terminal pin work --backend=wezterm<CR>", note = "pinned already" },
    { wait = [[_G.noted("pin: terminal 'work' already lives in wezterm")]] },

    { keys = ":Terminal adopt work<CR>", note = "the pane's screen in a read-only buffer" },
    { wait = [[vim.api.nvim_get_current_line() == "hello from the pane"]] },
    { expect = [[vim.bo.modifiable == false and vim.fn.line("$") == 2]] },
    { expect = [[vim.bo.buftype == "nofile"]], note = "a view: nothing to save" },
    { expect = [[_G.mux_called("get-text")]] },
    { keys = ":Terminal close work<CR>", note = "close kills the pane" },
    { wait = [[_G.mux_called("kill-pane") and _G.names() == ""]] },
  },
  manual = {
    "Inside real tmux and real WezTerm: :Terminal pin makes a pane that outlives Neovim, :Terminal adopt follows its screen",
  },
}
