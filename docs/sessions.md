# Terminals in sessions

With [sessions.nvim](https://github.com/WKDSteve/sessions.nvim) a session brings its terminals
back: the terminals of the project are written next to the session file when it is saved and
reopened when it is loaded. **No process is saved.** A reopened terminal is a fresh shell, or a
fresh start of its command, and it comes back **hidden**; `toggle` shows it.

The two plugins do not require each other. sessions.nvim fires two `User` events, terminal.nvim
listens:

| Event | Data | terminal.nvim |
|---|---|---|
| `SessionsSavePost` | `{ name, path, tab, root?, root_remap? }` | writes `.<session>.terminals.json` beside the session file |
| `SessionsLoadPost` | `{ name, path, tab, root?, root_remap? }` | reads it and reopens what is not there yet |

A tab snapshot (`:Session save-tab`) carries no terminals: `tab` is `true` and both events are
ignored.

## What is saved

For every live terminal of the project that runs in a native window: its **name**, **layout**,
**directory**, and the **command** when it was started with `run(cmd, { direct = true })`, with
the `close`, `title` and `float` that `run` was given: a restore starts the command again with the
same exit handling and window (shown again after `toggle`, the float has that title and size). A
sidecar entry with an unknown `close`, a `title` with control characters or a `float` key the
configuration would refuse (a `border` piece `nvim_open_win` would not take, among them) loses
that value, not the terminal. A command typed into a shell (`run`
without `direct`, `send`) is not recorded; the shell is. Terminals in a tmux or WezTerm pane are
left out: the multiplexer keeps them, Neovim does not have to.

A terminal started with `run(cmd, { direct = true, session = false })` is left out as well. A
restore cannot repeat `env` (a sidecar holds no secrets) or `on_open` (a function), so a plugin
that sets its terminal up in `on_open` (keymaps, buffer variables) keeps it out of the session
instead. A definition of the same name saved before (a terminal the last load did not bring
back) is dropped by the first save while such a terminal is open, and stays dropped after that
terminal is gone.

With no terminal left, the file is removed, so a session never brings back terminals it no longer
had.

## What happens on load

- A terminal that already exists under the same name is left alone. Loading a session twice, or
  with a terminal of that name open, neither duplicates nor replaces anything.
- A saved **command** is a recipe, and loading a session must not run it on its own accord.
  `sessions.commands` says what happens:

  | Value | Effect |
  |---|---|
  | `"ask"` (default) | once per load, when the session has any command: *Start the commands* / *Open plain shells* / *Skip the terminals*. Dismissing the prompt skips. |
  | `"run"` | start the commands |
  | `"never"` | open those terminals as plain shells |

  A session whose terminals are all plain shells is never asked about.
  The prompt lists every command with the directory it would run in; control characters of the file (also the Unicode ones that reorder, hide or smuggle text: bidi marks, zero width and invisible characters, separators, tag characters) are spelled out (a newline as `\x0a`) and a long entry is cut, so a sidecar from a shared or cloned session directory cannot hide what *Start the commands* runs.
- Every terminal starts in the **directory** it was started in. A terminal opened for a folder
  (`open({ dir = ... })`, "Terminal here" in a tree) comes back under its name, in that folder.
  - A shell whose directory is gone opens in the project's directory under the same name, and a
    warning names it. So does a shell whose directory now lies in another project (the session's
    terminals are this project's: one opened elsewhere would not be saved with it again).
  - A command whose directory is gone is **not** started anywhere else (it may build, clean or
    delete relative to where it runs): it is reported as not reopened and its definition is kept
    for the next save.
- What cannot be reopened is reported in one warning, and the rest is reopened anyway.

## Moved projects: `relative_paths` and `root_remap`

The directories follow sessions.nvim's
[portability](https://github.com/WKDSteve/sessions.nvim/blob/main/docs/portability.md) options,
which it passes along in the events:

- With `relative_paths = true` the events carry `root` (the working directory of the save, or the
  one a load re-anchored the session to). A directory inside it is written as
  `{{SESSION_ROOT}}/...`, and a load puts it below the `root` of that load: the same project
  checked out at another path, or on another machine, gets its terminals back in their folders.
  Directories outside the root stay absolute (only at a path boundary: `proj-backup` is not inside
  `proj`).
- With `root_remap` the events carry that table, and a load translates the absolute directories
  through it (old prefix -> new prefix, at a path boundary), as sessions.nvim does for the session
  file. A key (or target) in `~` form (`["~/work"] = "~/projects"`) stands for the path below the
  home directory, which is how the sidecar stores it; an explicit key for the same absolute path
  wins.
- A sidecar written before (or without these options) has absolute directories and loads as it
  always did. A relative directory loaded without a `root` (the option turned off since) is put
  below the working directory, where sessions.nvim re-anchors the session too.

## Options

```lua
require("terminal").setup({
  sessions = {
    enable = true,       -- false: do not listen to the events at all
    commands = "ask",    -- "ask" | "run" | "never"
  },
})
```

## Trade-offs

- The sidecar belongs to the session file by name and follows `:Session rename` (moved, replacing a
  leftover of the new name) and `:Session delete` (removed) through the `SessionsRenamePost` /
  `SessionsDeletePost` events. A sessions.nvim that does not fire them (older versions) leaves the
  sidecar behind; every save writes the file anew (or removes it), so a leftover never brings
  terminals back into a session saved later under that name.
- A load that did not bring a terminal back as saved (*Skip*, an unanswered prompt, a failed start, or a command replaced by a plain shell) keeps its definition for the rest of this Neovim run: the next save writes it again next to the live terminals, so it is not lost on a machine that cannot start it. A live terminal of the same name wins. The kept definitions are forgotten when Neovim exits; they stay in the sidecar until a save in a run that did not load that session overwrites it.
- Without `relative_paths` / `root_remap` the directory is a path on this machine. A session moved
  to another checkout or machine then has terminals whose directory is gone or lies elsewhere:
  their shells come back in the project's directory (see above), and a command is not started in
  a place it was not saved for. With the options, see
  [Moved projects](#moved-projects-relative_paths-and-root_remap).
