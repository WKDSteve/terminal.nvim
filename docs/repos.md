# Repository status

`:Terminal repos` opens a float with one line per repository in which a terminal is open, so a
red or stuck CI run, an unpushed commit or a dirty checkout is seen at a glance:

```
streamtap                local: clean                  CI: waiting for approval   -> testing ci trust o/streamtap abc1234
terminal.nvim            local: 3 changed, ahead 1     CI: green
```

Which repositories: the project roots of the terminals terminal.nvim knows (all projects, not
just the current one). Two terminals in one project show one line.

## Local state

From `git status --porcelain=v1 -b`: `clean`, `N changed` (staged, unstaged and untracked files
alike: in a shared checkout the changes of other sessions count too), `ahead N` (not pushed),
`behind N`. Asked at most every 5 seconds per repository.

## CI state

From `gh run list --event push`: the runs of the **newest pushed commit** (all its workflows);
the worst state wins.

| Shown | Meaning |
|---|---|
| `green` | every run succeeded |
| `RED` | a run failed in a step of the workflow |
| `running` | a run is in progress |
| `queued (runner off?)` | a run waits for a runner |
| `waiting for approval` | the runner guard refused the job; the command to approve follows the line |
| `cancelled`, `skipped`, `no run` | as named |
| `n/a (reason)` | `gh` is not installed, not logged in or offline; the reason is `gh`'s first message line |

Asked at most once a minute per repository, so `gh` is never polled in seconds. An offline
machine or a missing `gh` is a message in the line, never an error.

### Waiting for approval

The runner guard of testing.nvim (`docs/RUNNER-GUARD.md`) cancels the job of a commit of a public
repository that has not been reviewed. GitHub reports that as a plain `failure`. It is told from
a real failure by the steps: in a refused run every failed job failed only in its setup step
(`Set up runner`; `Set up job` on a GitHub-hosted runner), so no step of the workflow ran. That was
measured on the refused runs of streamtap (2026-11-03). If any failed job failed in another step
the run is `RED`.

## Keys in the float

| Key | Does |
|---|---|
| `r` | ask `git` and `gh` again now (ignores the intervals) |
| `y` | copy the approval command of the line (`testing ci trust <owner/repo> <sha>`) |
| `<CR>` | open the newest run of the line in the browser |
| `q`, `<Esc>` | close |

The float refreshes itself every 15 seconds while it is open; the intervals above still apply.

## Not covered

A desktop/web view of the same data is a separate task (tasks-desktop). Review the commit before
you run the approval command: it trusts the whole range up to that commit.
