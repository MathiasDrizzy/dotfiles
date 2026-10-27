# herdr-ctl: agent instructions

You maintain `herdr-ctl`, a Go tool (stdlib only) that feeds herdr's sidebar on macOS. Read `README.md` first.

## Layout

- `sidebar.go`: usage cache and merge (newest reading wins), state labels, git/CI reading, the syncer that reports to herdr (deduplicated), the focus pass.
- `watch.go`: the event-driven watcher (`spaces-watch`): subscribes to herdr's socket, settles bursts, one full pass a minute, single-instance lock.
- `main.go`: CLI entry and `callRPC` (socket client, always with deadlines).
- `plugin/herdr-plugin.toml`: how herdr starts the watcher.
- `keymap.go`, `cheatsheet.go`: helper commands.

## Hard-won facts

- Report over the socket (`pane.report_metadata`), not by spawning the `herdr` CLI: a spawn costs ~300 ms.
- Never subscribe to `*.updated`/metadata events: our own reports raise them and it loops.
- A losing agent is dimmed before the gaining one is brightened, so two bright names are never on screen.
- Only `workspace` tokens are colored by herdr's focus; the agent name's color is done with two tokens (`aname_dim` / `aname_hot`).
- Every outside command (herdr, git, gh) has a timeout; `git` runs with `--no-optional-locks`.

## Checks

`scripts/go-checks.sh` must pass (it is what CI runs). Test first: observe the test fail, then fix.

## Rules for every change

- Conventional Commits (`feat(scope): ...`), one reviewable unit per commit with its tests and docs. No AI attribution or `Co-Authored-By` lines.
- Artifacts (code, comments, docs, commit messages) are in English; the maintainer talks to you in Spanish.
- This repository is public: never commit secrets, tokens, IPs of a private network, or precise personal coordinates.
- Nothing hardcoded to one machine, repository, space or agent name: it must work for anyone.
- Cost matters more than features: keep idle CPU near zero and RAM small. Prefer events over polling; any polling needs a stated reason and a measured cost. Never leave a background process looping, hung or forgotten.
- Work on a branch, push it as `ci/<name>` to run CI, merge to `main` only when green. Do not push to `main` untested.
- The `dotfiles` repository pins this one as a submodule (`mac/tools/<name>`); after merging here, bump the pointer there.
