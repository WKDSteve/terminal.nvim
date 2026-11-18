-- Inside Kitty, the padding is made snug while Neovim edits (`kitty @ set-spacing` at start) and restored when it
-- leaves (on VimLeavePre, waited for). `kitty` is a recording stand-in on the PATH: the commands are checked, that
-- real Kitty changes its padding is a person's check.
return {
  id = "terminal.kitty-padding",
  feature = "terminal.kitty-padding",
  title = "terminal.nvim: inside Kitty the padding is snug while editing and restored on exit",
  task = "terminal.nvim/performance-pruefung-luecken-schliessen-katalog-feature-shee",
  fakes = { "kitty" },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
      -- Neovim runs inside Kitty with remote control on.
      vim.env.KITTY_LISTEN_ON = "unix:/tmp/kitty-sheet"
      _G.setup({ kitty = { enter_padding = 1, enter_margin = 2, leave_padding = 20, leave_margin = 10 } })
      ---Whether the `n`th call of the stand-in set the spacing to `padding` and `margin`. A `.cmd` stand-in on Windows
      ---splits `padding=1` at the `=` (cmd.exe takes it for a separator): there only the call itself is checked.
      _G.spacing = function(n, padding, margin)
        local call = _G.fake_calls("kitty")[n]
        if not (call and call.argv[1] == "@" and call.argv[2] == "set-spacing") then
          return false
        end
        return vim.fn.has("win32") == 1
          or (call.argv[3] == "padding=" .. padding and call.argv[4] == "margin=" .. margin)
      end]],
    },

    {
      wait = [[_G.spacing(1, 1, 2)]],
      timeout = 5000,
      note = "setup after VimEnter: the snug padding at once",
    },
    {
      lua = [[vim.api.nvim_exec_autocmds("VimLeavePre", {})]],
      note = "Neovim is about to leave",
    },
    {
      expect = [[_G.spacing(2, 20, 10) and #_G.fake_calls("kitty") == 2]],
      note = "the padding is restored before the editor goes (the start was waited for)",
    },
  },
  manual = {
    "In real Kitty with allow_remote_control: the padding shrinks when Neovim starts and comes back when it quits",
  },
}
