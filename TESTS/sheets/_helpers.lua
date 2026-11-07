-- TESTS/sheets/_helpers.lua -- what the terminal.nvim test sheets need in their child editor. Not a sheet
-- (`testing.sheet` only reads *.sheet.lua); a sheet's first step runs it with `dofile`, the child's cwd is the
-- project root. The directory is in the spec's @cache-inputs, so a change here re-runs the sheets.
--
-- The terminals of the sheets are real: a real interactive shell behind a real pty, in a temp directory. WezTerm and
-- tmux are not started: `_G.fake_multiplexer` hands the backend the fake CLI of TESTS/support/fakes.lua.

_G.ROOT = vim.fs.normalize(vim.fn.getcwd())

vim.opt.shortmess:append("I")
vim.o.swapfile = false
vim.o.hidden = true

-- A sheet may run inside a multiplexer: what the plugin would hand off to must not be the real one.
vim.env.TMUX = nil
vim.env.TMUX_PANE = nil
vim.env.WEZTERM_PANE = nil

-- The terminal's working directory is the project of the current directory: a temp directory, so what a sheet makes
-- its shell write stays out of the repository.
_G.DIR = vim.fs.normalize(vim.fn.tempname())
vim.fn.mkdir(_G.DIR, "p")
vim.cmd.cd(vim.fn.fnameescape(_G.DIR))

---What the plugin said so far (a long message would otherwise wait at a hit-enter prompt).
---@type string[]
_G.NOTES = {}
vim.notify = function(msg)
  _G.NOTES[#_G.NOTES + 1] = tostring(msg)
end

---Whether the plugin said `text` (plain).
---@param text string
---@return boolean
function _G.noted(text)
  return table.concat(_G.NOTES, "\n"):find(text, 1, true) ~= nil
end

---The real shell of the platform, interactive.
---@return string[]
local function shell()
  return vim.fn.has("win32") == 1 and { "cmd.exe" } or { "sh" }
end

---Set the plugin up with a real shell.
---@param opts table|nil
function _G.setup(opts)
  require("terminal").setup(vim.tbl_deep_extend("force", { shell = shell() }, opts or {}))
end

---The terminal `name` of this project, also one whose job has ended.
---@param name string
---@return Terminal.Handle|nil
function _G.term_any(name)
  for _, h in ipairs(require("terminal").list()) do
    if h.name == name then
      return h
    end
  end
  return nil
end

---The live terminal `name` of this project.
---@param name string
---@return Terminal.Handle|nil
function _G.term(name)
  local h = _G.term_any(name)
  return h and not h.exited and h or nil
end

---The names of this project's terminals, sorted and joined.
---@return string
function _G.names()
  local names = require("terminal").names()
  table.sort(names)
  return table.concat(names, ",")
end

---The window that shows terminal `name`, or nil when it is hidden or gone.
---@param name string
---@return integer|nil
function _G.win_of(name)
  local h = _G.term(name)
  if not h then
    return nil
  end
  local win = vim.fn.bufwinid(h.bufnr)
  return win ~= -1 and win or nil
end

---The text of terminal `name`.
---@param name string
---@return string
function _G.text(name)
  local h = _G.term_any(name)
  return h and table.concat(vim.api.nvim_buf_get_lines(h.bufnr, 0, -1, false), "\n") or ""
end

---Whether terminal `name` shows `word` (plain) at least `times` times (default once).
---@param name string
---@param word string
---@return boolean
function _G.shows(name, word)
  -- Without the line ends: a long prompt (the temp path) wraps what is typed behind it at any place.
  return _G.text(name):gsub("\n", ""):find(word, 1, true) ~= nil
end

---Whether the shell has printed its first prompt (it reads what is typed from then on).
---@param name string
---@return boolean
function _G.ready(name)
  return vim.trim(_G.text(name)) ~= ""
end

---Whether a file of the terminal's directory exists and holds `word`.
---@param file string
---@param word string
---@return boolean
function _G.wrote(file, word)
  local path = _G.DIR .. "/" .. file
  return vim.uv.fs_stat(path) ~= nil
    and table.concat(vim.fn.readfile(path), "\n"):find(word, 1, true) ~= nil
end

---Whether the current window is a float.
---@return boolean
function _G.in_float()
  return vim.api.nvim_win_get_config(0).relative ~= ""
end

---The WezTerm backend on the fake CLI: nothing is started, every call is recorded. `_G.MUX` is the state of the fake.
---Call before the first `:Terminal pin` or `:Terminal adopt`.
---@param panes_text string|nil what the pane's screen shows
function _G.fake_multiplexer(panes_text)
  local fakes = dofile(_G.ROOT .. "/TESTS/support/fakes.lua")
  local run, state = fakes.wezterm()
  state.text = panes_text
  _G.MUX = state
  local wezterm = require("terminal.backends.wezterm")
  local new = wezterm.new
  wezterm.available = function()
    return true, nil
  end
  wezterm.new = function(registry)
    return new(registry, run, "7")
  end
end

---Whether the fake multiplexer was asked for `sub` (`split-pane`, `kill-pane`, ...).
---@param sub string
---@return boolean
function _G.mux_called(sub)
  for _, call in ipairs(_G.MUX.calls) do
    if call.argv[1] == sub then
      return true
    end
  end
  return false
end
