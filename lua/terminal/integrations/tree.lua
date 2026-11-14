---@module 'terminal.integrations.tree'
--- "Terminal here" as an action on a node of a tree view.
---
--- Registers one action at `lib.nvim.tree.registry`. A tree that reads the registry (the own tree
--- of filetree.nvim) offers it on every node that is a file or a folder on disk: in its context
--- menu, in its action list, and on a key when one is configured. It opens the terminal of the
--- node's folder (`require("terminal").open({ dir = ... })`): a folder is itself, a file means the
--- folder it lies in. That terminal is found again by the folder, so the action on the same node
--- shows the terminal that is already there.
---
--- Soft in both directions. The registry is lib.nvim's: without a tree that reads it the entry is
--- never looked at, and without a lib.nvim that has the registry nothing is registered.

local M = {}

M.NAME = "terminal.here"

---@type (fun(): boolean)|nil
local unregister = nil

--- The folder a node stands for: a folder is itself, anything else the folder it lies in.
---@param path string
---@return string
function M.folder_of(path)
  if vim.fn.isdirectory(path) == 1 then
    return path
  end
  return vim.fs.dirname(path)
end

--- Open the terminal of the folder of `path` and focus it.
---@param path string A file or a folder
---@return Terminal.Handle|nil handle
---@return string|nil err
function M.open_at(path)
  return require("terminal").open({ dir = M.folder_of(path) })
end

--- Register the action. Without `lib.nvim.tree.registry` (an older lib.nvim) nothing happens.
---@param opts? Terminal.TreeOptions
---@return boolean registered
function M.register(opts)
  local ok, registry = pcall(require, "lib.nvim.tree.registry")
  if not ok or type(registry.action) ~= "function" then
    return false
  end
  M.unregister()
  opts = opts or {}
  unregister = registry.action({
    name = M.NAME,
    desc = "Terminal here (terminal.nvim)",
    key = opts.key or nil,
    needs = { "path" },
    run = function(nodes)
      -- `Lib.Tree.Node` does not declare the path a file node carries (`needs = { "path" }`)
      local node = nodes and nodes[1] --[[@as { path?: string }|nil]]
      if not (node and type(node.path) == "string" and node.path ~= "") then
        return
      end
      -- one terminal takes the focus: with several nodes marked, say which folder it is instead
      -- of leaving the others out silently
      if #nodes > 1 then
        require("terminal.notify").warn(
          ("%d nodes are marked; opening the terminal of the first only: %s"):format(
            #nodes,
            node.path
          )
        )
      end
      M.open_at(node.path)
    end,
  })
  return true
end

--- Take the action out again.
---@return nil
function M.unregister()
  if unregister then
    unregister()
    unregister = nil
  end
end

return M
