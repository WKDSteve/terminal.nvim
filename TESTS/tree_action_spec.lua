---@diagnostic disable: need-check-nil, undefined-field, redundant-parameter
-- need-check-nil, undefined-field and redundant-parameter are off for the whole file: a nil in a spec body fails the next assertion anyway, luassert's assert.* and the stubbed vim.* fields are not in the annotations, and luassert takes a failure message as its last argument, which its type stub does not declare.
-- TESTS/tree_action_spec.lua -- the action `terminal.here` at lib.nvim.tree.registry
-- (`terminal.integrations.tree`), which the own tree of filetree.nvim reads. Checked here are the
-- entry and what its `run` does with a node; that a tree offers a registered action on a key and in
-- its menu is filetree.nvim's own spec.

-- Hermetic: no multiplexer variables from the terminal the specs are run in.
dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".") .. "/support/env.lua").isolate()

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local jobs = dofile(here .. "/support/jobs.lua")

describe("terminal.integrations.tree", function()
  local terminal, tree, registry
  local base, folder, file, saved_cwd

  ---@param extra? table
  local function setup(extra)
    terminal.setup(vim.tbl_extend("force", {
      shell = jobs.sleeper(),
      start_insert = false,
      commands = false,
      keymaps = { preset = false },
    }, extra or {}))
  end

  ---@return table|nil
  local function entry()
    return registry.get("action", tree.NAME)
  end

  before_each(function()
    for _, mod in ipairs({
      "terminal",
      "terminal.config",
      "terminal.backends.native",
      "terminal.bindings",
      "terminal.integrations.tree",
    }) do
      package.loaded[mod] = nil
    end
    registry = require("lib.nvim.tree.registry")
    registry.reset()
    terminal = require("terminal")
    tree = require("terminal.integrations.tree")

    saved_cwd = vim.fn.getcwd()
    base = vim.fs.normalize(vim.fn.tempname() .. "-terminal-tree")
    folder = base .. "/proj/my docs"
    file = folder .. "/a b.md"
    vim.fn.mkdir(base .. "/proj/.git", "p")
    vim.fn.mkdir(folder, "p")
    vim.fn.writefile({ "x" }, file)
    vim.cmd("cd " .. vim.fn.fnameescape(base .. "/proj"))
  end)

  after_each(function()
    for _, h in ipairs(terminal.list(true)) do
      jobs.settle()
      terminal.close({ name = h.name })
    end
    vim.cmd("silent! only")
    registry.reset()
    vim.cmd("cd " .. vim.fn.fnameescape(saved_cwd))
    vim.fn.delete(base, "rf")
  end)

  --- Run `fn` with `terminal.open` replaced by a recorder and return the targets it was given.
  ---@param fn fun()
  ---@return table[] targets
  local function record_opens(fn)
    local targets = {}
    local original = terminal.open
    -- Test double: records the target instead of opening a terminal; restored below.
    ---@diagnostic disable-next-line: duplicate-set-field
    terminal.open = function(target)
      targets[#targets + 1] = target
      return {}, nil
    end
    local ok, err = pcall(fn)
    terminal.open = original
    if not ok then
      error(err, 0)
    end
    return targets
  end

  it("setup registers the action at the tree registry", function()
    setup()
    local action = entry()
    assert.is_not_nil(action)
    assert.same({ "path" }, action.needs)
    assert.is_nil(action.key, "without a configured key it has none")
    assert.is_nil(action.mutates, "opening a terminal changes no file")
    assert.is_true(type(action.desc) == "string" and action.desc ~= "")
  end)

  it("on a folder it opens the terminal of that folder", function()
    setup()
    local targets = record_opens(function()
      entry().run({ { path = folder, kind = "dir" } }, {})
    end)
    assert.same({ { dir = folder } }, targets)
  end)

  it("a file means the folder it lies in", function()
    setup()
    local targets = record_opens(function()
      entry().run({ { path = file, kind = "file" } }, {})
    end)
    assert.same({ { dir = folder } }, targets)
  end)

  it("a node without a path, or none, opens nothing", function()
    setup()
    local targets = record_opens(function()
      entry().run({ { id = "heading", kind = "group" } }, {})
      entry().run({ { path = "" } }, {})
      entry().run({}, {})
      entry().run(nil, {})
    end)
    assert.same({}, targets)
  end)

  it("with several nodes marked it opens the first and says which one", function()
    setup()
    local targets
    local messages = jobs.capture_notify(function()
      targets = record_opens(function()
        entry().run({ { path = folder }, { path = base .. "/proj" } }, {})
      end)
      vim.wait(100, function()
        return false
      end)
    end)
    assert.same({ { dir = folder } }, targets)
    assert.equals(1, #messages)
    assert.truthy(messages[1]:find("2 nodes", 1, true), messages[1])
    assert.truthy(messages[1]:find(folder, 1, true), messages[1])
  end)

  it("for real: the terminal starts in the folder of the node and is found again there", function()
    setup()
    entry().run({ { path = file, kind = "file" } }, {})
    local list = terminal.list()
    assert.equals(1, #list)
    assert.equals("my docs/", list[1].name)
    assert.equals(folder, list[1].cwd)
    assert.equals(list[1].bufnr, vim.api.nvim_get_current_buf(), "it has the focus")
    vim.cmd("wincmd p")
    entry().run({ { path = folder, kind = "dir" } }, {})
    assert.equals(1, #terminal.list(), "the same node again is the same terminal")
    assert.equals(list[1].bufnr, vim.api.nvim_get_current_buf())
  end)

  describe("the option `tree`", function()
    it("{ key = ... } puts the action on that key, as one entry", function()
      setup({ tree = { key = "<leader>t" } })
      assert.equals("<leader>t", entry().key)
      setup({ tree = { key = { "<leader>t", "gt" } } })
      assert.same({ "<leader>t", "gt" }, entry().key)
      local count = 0
      for _, e in ipairs(registry.list("action")) do
        if e.name == tree.NAME then
          count = count + 1
        end
      end
      assert.equals(1, count)
    end)

    it("a key of false, or an empty table, offers it without a key", function()
      setup({ tree = { key = false } })
      assert.is_not_nil(entry())
      assert.is_nil(entry().key)
      setup({ tree = {} })
      assert.is_not_nil(entry())
      assert.is_nil(entry().key)
    end)

    it("false takes the action out; the default offers it again", function()
      setup()
      setup({ tree = false })
      assert.is_nil(entry())
      setup()
      assert.is_not_nil(entry())
    end)

    it("a value that is none is reported and the default stays", function()
      local config = require("terminal.config")
      for _, bad in ipairs({
        "yes",
        3,
        { key = 7 },
        { key = "" },
        { key = { "a", 2 } },
        { keys = "x" },
      }) do
        jobs.capture_notify(function()
          setup({ tree = bad })
          vim.wait(50, function()
            return false
          end)
        end)
        assert.equals(1, #config.problems, vim.inspect(bad))
        assert.truthy(config.problems[1]:find("config key 'tree'", 1, true), config.problems[1])
        assert.is_true(config.get("tree"), vim.inspect(bad))
        assert.is_not_nil(entry(), vim.inspect(bad))
        assert.is_nil(entry().key, vim.inspect(bad))
      end
    end)
  end)

  it("unregister removes the entry, twice is harmless, and never somebody else's", function()
    setup()
    tree.unregister()
    assert.is_nil(entry())
    tree.unregister()
    assert.is_nil(entry())
    assert.is_true(tree.register())
    local remove_other = registry.action({ name = tree.NAME, run = function() end })
    tree.unregister()
    assert.is_not_nil(entry(), "an entry that replaced ours stays")
    remove_other()
  end)
end)
