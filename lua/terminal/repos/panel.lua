---@module 'terminal.repos.panel'
--- The view of the repository status area: a small float with one line per repository of the open
--- terminals. It refreshes itself while it is open (the data layer throttles the questions), and
--- offers `r` (ask again now), `y` (copy the approval command of the line), `<CR>` (open the run
--- in the browser) and `q`.
---@see terminal.repos

local repos = require("terminal.repos")

local M = {}

--- Seconds between two refreshes while the panel is open.
M.REFRESH_MS = 15000

---@class Terminal.RepoPanelState
---@field buf? integer
---@field win? integer
---@field timer? userdata
---@field rows Terminal.RepoRow[]

---@class Terminal.RepoPanelOpts
---@field list? fun(all?: boolean): { root?: string }[] Default `terminal.list`
---@field collect? Terminal.RepoCollectOpts Test hook: handed to `terminal.repos.collect`
---@field force? boolean
---@field timer? boolean `false`: no refresh timer (specs)

---@type Terminal.RepoPanelState
local state = { rows = {} }

---@return boolean
function M.is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

---@return nil
function M.close()
  if state.timer then
    state.timer:stop()
    if not state.timer:is_closing() then
      state.timer:close()
    end
    state.timer = nil
  end
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    pcall(vim.api.nvim_win_close, state.win, true)
  end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
  end
  state.win, state.buf, state.rows = nil, nil, {}
end

--- The lines of the panel for `rows`.
---@param rows Terminal.RepoRow[]
---@return string[]
function M.lines(rows)
  if #rows == 0 then
    return { "no repositories: open a terminal in a project first" }
  end
  local out = {}
  for i, row in ipairs(rows) do
    out[i] = repos.format(row)
  end
  return out
end

---@param rows Terminal.RepoRow[]
local function render(rows)
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
    return
  end
  state.rows = rows
  local lines = M.lines(rows)
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  if M.is_open() then
    local width = 20
    for _, l in ipairs(lines) do
      width = math.max(width, vim.fn.strdisplaywidth(l) + 2)
    end
    width = math.min(width, vim.o.columns - 4)
    local height = math.max(1, math.min(#lines, vim.o.lines - 6))
    pcall(vim.api.nvim_win_set_config, state.win, {
      relative = "editor",
      width = width,
      height = height,
      row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
      col = math.floor((vim.o.columns - width) / 2),
    })
  end
end

--- Ask the data layer and redraw.
---@param opts? Terminal.RepoPanelOpts
---@return nil
function M.refresh(opts)
  opts = opts or {}
  local list = opts.list or require("terminal").list
  local roots = repos.open_roots(list)
  repos.collect(
    roots,
    vim.tbl_extend("force", { force = opts.force }, opts.collect or {}),
    function(rows)
      render(rows)
    end
  )
end

---@return Terminal.RepoRow|nil
local function row_under_cursor()
  if not M.is_open() then
    return nil
  end
  return state.rows[vim.api.nvim_win_get_cursor(state.win)[1]]
end

--- Open (or focus) the panel.
---@param opts? Terminal.RepoPanelOpts
---@return integer buf
function M.open(opts)
  opts = opts or {}
  if M.is_open() then
    vim.api.nvim_set_current_win(state.win)
    M.refresh(opts)
    return state.buf
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "terminal-repos"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "asking git and gh ..." })
  vim.bo[buf].modifiable = false
  local width = 40
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = 1,
    row = math.floor(vim.o.lines / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " Repositories ",
  })
  state.buf, state.win = buf, win

  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, desc = desc })
  end
  map("q", M.close, "Close the repository status")
  map("<Esc>", M.close, "Close the repository status")
  map("r", function()
    M.refresh(vim.tbl_extend("force", opts, { force = true }))
  end, "Ask git and gh again now")
  map("y", function()
    local row = row_under_cursor()
    if row and row.trust then
      vim.fn.setreg("+", row.trust)
      vim.fn.setreg('"', row.trust)
      require("terminal.notify").info("copied: " .. row.trust)
    elseif row then
      require("terminal.notify").info(row.name .. ": nothing to approve")
    end
  end, "Copy the approval command of the repository")
  map("<CR>", function()
    local row = row_under_cursor()
    if row and row.run_url and row.run_url:match("^https?://") then
      vim.ui.open(row.run_url)
    end
  end, "Open the newest CI run in the browser")

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      vim.schedule(M.close)
    end,
  })

  M.refresh(opts)
  if opts.timer ~= false then
    state.timer = assert(vim.uv.new_timer())
    state.timer:start(M.REFRESH_MS, M.REFRESH_MS, function()
      vim.schedule(function()
        if M.is_open() then
          M.refresh(opts)
        else
          M.close()
        end
      end)
    end)
  end
  return buf
end

return M
