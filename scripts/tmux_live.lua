-- scripts/tmux_live.lua -- the tmux live smokes (TESTS/live/tmux.lua and nested.lua) as one pipeline step.
--
--   nvim -n -i NONE --headless -u NONE -l scripts/tmux_live.lua
--
-- The live scripts write one line per check to $SMOKE_OUT and always exit 0; this runs each of them in a
-- child Neovim and is red unless every output file ends in "RESULT ok". Without tmux on PATH it exits 77
-- (the step's `skip_exit`): nothing could be checked here. LIB_NVIM_DIR is passed through to the children.

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h"):gsub("\\", "/")

if vim.fn.executable("tmux") == 0 then
  io.stdout:write("tmux_live: skipped, tmux is not on PATH\n")
  os.exit(77)
end

---@type { script: string, env?: table<string, string> }[]
local RUNS = {
  { script = "TESTS/live/tmux.lua" },
  { script = "TESTS/live/nested.lua" },
  -- an NVIM_APPNAME with a dot and a dash: the exporter's ownership check must not depend on the default name
  { script = "TESTS/live/nested.lua", env = { NVIM_APPNAME = "my-app.v2" } },
}

local failed = false
for _, run in ipairs(RUNS) do
  local out_file = vim.fn.tempname()
  local env = { SMOKE_OUT = out_file }
  for k, v in pairs(run.env or {}) do
    env[k] = v
  end
  local label = run.script .. (run.env and (" " .. vim.inspect(run.env, { newline = "" })) or "")
  io.stdout:write(("== %s\n"):format(label))
  local argv = { vim.v.progpath, "-n", "-i", "NONE", "--headless", "-u", "NONE", "-l" }
  argv[#argv + 1] = root .. "/" .. run.script
  local child = vim.system(argv, { cwd = root, env = env, text = true })
  local res = child:wait(120000)
  local fd = io.open(out_file, "r")
  local text = fd and fd:read("*a") or ""
  if fd then
    fd:close()
  end
  os.remove(out_file)
  io.stdout:write(text)
  local last = text:gsub("%s+$", ""):match("([^\n]*)$")
  if last ~= "RESULT ok" then
    failed = true
    io.stdout:write(
      ("FAIL %s: exit %s, last line %q\n"):format(label, tostring(res.code), last or "")
    )
    if res.stderr and res.stderr ~= "" then
      io.stdout:write(res.stderr)
    end
  end
end

io.stdout:write(failed and "tmux_live: failed\n" or "tmux_live: ok\n")
os.exit(failed and 1 or 0)
