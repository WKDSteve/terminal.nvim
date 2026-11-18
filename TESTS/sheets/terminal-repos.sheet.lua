-- :Terminal repos asks a real `git status` in the project of each open terminal and `gh run list` for its CI. `gh` is
-- a recording stand-in on the PATH (no account, no network in a sheet): it answers nothing, which the float shows as
-- "n/a"; a real CI state is a person's check.
return {
  id = "terminal.repos",
  feature = "terminal.repos",
  title = "terminal.nvim: :Terminal repos shows the local git state and the CI line of the terminals' repositories",
  task = "terminal.nvim/performance-pruefung-luecken-schliessen-katalog-feature-shee",
  fakes = { "gh" },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
      _G.setup()
      -- The terminal's project is a git repository with one new file.
      vim.system({ "git", "init", "-q", _G.DIR }):wait()
      vim.fn.writefile({ "x" }, _G.DIR .. "/new.txt")
      ---The text of the repos float.
      _G.float_text = function()
        if vim.bo.filetype ~= "terminal-repos" then
          return ""
        end
        return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
      end]],
    },

    { keys = ":Terminal open r --layout=split<CR>", note = "a terminal in the project" },
    { wait = [[_G.ready("r")]], timeout = 8000 },
    { input = "<C-\\><C-n>:Terminal repos<CR>", note = "the float of the repositories" },
    {
      wait = [[_G.float_text():find("local: 1 changed", 1, true) ~= nil]],
      timeout = 8000,
      note = "git found the new file",
    },
    {
      wait = [[_G.float_text():find("gh returned no JSON", 1, true) ~= nil]],
      timeout = 8000,
      note = "the CI part asked gh; the stand-in answered nothing",
    },
    {
      expect = [[_G.fake_called("gh", { "run", "list", "--event", "push" })]],
      note = "gh was asked for the push runs",
    },
    { expect = [[_G.in_float()]] },
    { keys = "q", note = "q closes it" },
    { wait = [[vim.bo.filetype ~= "terminal-repos"]] },
  },
  manual = {
    "In a repository with a pushed commit and gh logged in: the CI column shows green / RED / running",
  },
}
