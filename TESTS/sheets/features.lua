-- TESTS/sheets/features.lua -- the functionalities of terminal.nvim as its user meets them; `testing sheets report`
-- says which ones have a feature sheet (`feature = "<id>"`) and in which state, and K16 warns about a sheet that names
-- an id not listed here. Data: read with an empty environment like a sheet (testing.nvim docs/SHEETS.md).
-- The list follows README.md and docs/README.md (one page per functionality).
return {
  {
    id = "terminal.toggle",
    title = "<A-h> toggles a named per-project terminal (float, split, vsplit or tab) that keeps running while hidden",
    surface = {
      "command:Terminal toggle",
      "command:Terminal open",
      "command:Terminal hide",
      "command:Terminal close",
    },
    docs = "docs/commands.md",
  },
  {
    id = "terminal.send",
    title = ":Terminal send types a line, a selection or a file into the terminal; :Terminal run quotes for the shell",
    surface = { "command:Terminal send", "command:Terminal run" },
    docs = "docs/commands.md",
  },
  {
    id = "terminal.list",
    title = ":Terminal list picks one of the project's terminals and sends a line to it",
    surface = { "command:Terminal list" },
    docs = "docs/commands.md",
  },
  {
    id = "terminal.cheat",
    title = ":Terminal cheat shows the cheatsheet of the terminal's shell one section at a time and types a line",
    surface = { "command:Terminal cheat" },
    docs = "docs/cheatsheet.md",
  },
  {
    id = "terminal.navigate",
    title = "<C-h/j/k/l> move between windows with a count and hand off into the neighbouring tmux or WezTerm pane",
    docs = "docs/navigation.md",
  },
  {
    id = "terminal.backends",
    title = "Terminals run as Neovim's own :terminal or as panes of tmux or WezTerm",
    docs = "docs/backends.md",
    -- The native backend is what every other sheet measures; tmux and WezTerm panes are processes of a running
    -- multiplexer that the sheets replace with an in-memory CLI (TESTS/support/fakes.lua).
    perf = "manual:tmux and WezTerm panes need a running multiplexer server or GUI (the native backend is measured by every sheet)",
  },
  {
    id = "terminal.pin-adopt",
    title = ":Terminal pin restarts a native terminal as a tmux/WezTerm pane that outlives Neovim; adopt shows a pane read-only",
    surface = { "command:Terminal pin", "command:Terminal adopt" },
    docs = "docs/backends.md",
  },
  {
    id = "terminal.sessions",
    title = "The terminals of a sessions.nvim session are saved with it and reopened hidden on load",
    docs = "docs/sessions.md",
  },
  {
    id = "terminal.ask",
    title = "A git hook or a script in a terminal asks its question in a Neovim dialog",
    docs = "docs/ask.md",
    perf = "skip:the plugin starts no process for it; the client nvim-ask runs in the terminal's own shell and asks over RPC",
  },
  {
    id = "terminal.repos",
    title = ":Terminal repos shows local state and CI of the repositories of the open terminals",
    surface = { "command:Terminal repos" },
    docs = "docs/repos.md",
  },
  {
    id = "terminal.status-export",
    title = "Mode, file, branch and diagnostics are exported to tmux and the WezTerm tab title and status",
    docs = "docs/status.md",
  },
  {
    id = "terminal.kitty-padding",
    title = "Inside Kitty the window padding is snug while Neovim edits and restored when it quits",
    surface = { "config:kitty.enable" },
    docs = "docs/configuration.md",
  },
}
