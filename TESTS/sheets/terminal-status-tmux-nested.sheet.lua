-- Inside tmux with `$NVIM` set (this Neovim's pane belongs to a tmux server that was started from another Neovim's
-- terminal, or this Neovim runs in that terminal): the tmux exporter asks the outer Neovim for its pid with a short
-- `nvim --server <address> --remote-expr getpid()`. That check runs in the background from the first publication on,
-- the start never waits for it. The outer Neovim here is a real second server that this child starts; it is no
-- ancestor of this editor, so the pane is this one's and the status goes out once the check answered (Windows cannot
-- read the process tree: the nesting stays unknown, the status goes out anyway with one warning). `tmux` is a
-- recording stand-in on the PATH.
return {
  id = "terminal.status-tmux-nested",
  feature = "terminal.status-export",
  title = "terminal.nvim: with $NVIM set, the nesting check runs in the background and the status follows",
  task = "terminal.nvim/handlauf-status-export-mit-nvim-in-echtem-tmux",
  fakes = { "tmux" },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
      -- A real second Neovim server plays the outer Neovim that $NVIM names.
      _G.outer_address = vim.fn.has("win32") == 1
          and ("\\\\.\\pipe\\terminal-sheet-outer-" .. vim.uv.os_getpid())
        -- short on purpose: a unix socket path ends at ~104 bytes, and the temp dir of a CI snapshot is longer
        or ("/tmp/terminal-sheet-outer-" .. vim.uv.os_getpid() .. ".sock")
      _G.outer = vim.fn.jobstart({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "--listen", _G.outer_address })]],
    },
    {
      expect = [[_G.outer > 0]],
      note = "the outer Neovim server was started",
    },
    {
      wait = [[require("terminal.status.nested").alive(_G.outer_address)]],
      timeout = 15000,
      note = "the outer Neovim server answers on its address",
    },
    {
      lua = [[vim.env.TMUX = "/tmp/tmux-1000/default,1,0"
      vim.env.TMUX_PANE = "%7"
      vim.env.NVIM = _G.outer_address
      local t0 = vim.uv.hrtime()
      _G.setup()
      _G.setup_ms = (vim.uv.hrtime() - t0) / 1e6]],
      note = "set up inside tmux pane %7, $NVIM names the outer server",
    },
    {
      expect = [[_G.setup_ms < 1000]],
      note = "setup does not wait for the outer server (it used to ask it right there)",
    },
    {
      wait = [[_G.fake_called("tmux", { "set-option", "-p", "-t", "%7", "@terminal_branch" })]],
      timeout = 8000,
      note = "the status goes out once the check answered: the outer server is no ancestor of this editor",
    },
    {
      expect = [[#require("terminal.status").active() == 1]],
      note = "the tmux exporter stays in use",
    },
    { lua = [[vim.fn.jobstop(_G.outer)]] },
  },
  manual = {
    "Neovim inside a :terminal of another Neovim, inside real tmux: the outer one's status stays in the pane",
  },
}
