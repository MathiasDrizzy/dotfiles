# herdr-ctl

Small Go tool that makes [herdr](https://herdr.dev) (the terminal multiplexer) show live, useful sidebar rows on macOS:

- **Spaces**: for each repository a space's panes are in, its branch, commits not pushed, files changed and the last CI run, as a tree.
- **Agents**: each agent's name (bright for the one in front, dim for the rest, followed live from herdr's focus events), model, context and the account's real 5-hour and weekly usage, one row per window, and a "sin tokens" state when a window is used up.
- Also a Claude Code status line (`herdr-ctl statusline`) and a few helpers (`move-tab`, `swarm`, `keys-check`, ...).

## How it runs

`herdr-ctl spaces-watch` follows herdr's events over its socket (no polling except one pass a minute for CI). It runs as a herdr plugin, not a launchd job: macOS delays a launchd job's wakeups by about 100 ms, a process in herdr's own tree does not (measured). A lock file keeps a single copy alive.

```sh
go build -ldflags="-s -w" -o ~/.local/bin/herdr-ctl
herdr plugin link plugin               # starts with herdr; or: herdr plugin action invoke start --plugin dev.dotfiles.spaces-sync
```

The sidebar rows are configured in herdr's `config.toml` with custom tokens (`$aname_dim`, `$aname_hot`, `$model`, `$ctx`, `$limits5h`, `$limitsWeek`, `$repoN`...); see the [dotfiles](https://github.com/MathiasDrizzy/dotfiles) repository for the config in use.

## Development

```sh
scripts/go-checks.sh   # go vet, go test -race, golangci-lint, govulncheck (what CI runs)
```
