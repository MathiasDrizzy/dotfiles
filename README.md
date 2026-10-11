# macOS dotfiles — terminal setup

Terminal configuration for macOS (Apple Silicon): **Ghostty + herdr + zsh + Catppuccin Mocha**, with the everyday TUIs. It is designed to be reinstalled in full after reformatting.

## Layout

```
dotfiles/
├── mac/
│   ├── install.sh              # idempotent installer (--dry-run, --links-only)
│   ├── zshrc / zshenv          # interactive shell and global PATH
│   ├── config/                 # ghostty, herdr, yazi, micro, starship, termscp, lazygit, lazydocker, btop, bat
│   ├── scripts/                # check-links.sh, herdr-reload.sh, terminal-popup.sh
│   └── tools/herdr-ctl/        # Go tool: cheatsheet, adapt, agent bus, keys-check
├── scripts/
│   ├── harness-quick.sh        # quick harness (run by the pre-commit hook)
│   ├── harness-behavior.py     # behavior harness against an isolated herdr
│   ├── test-install-full.sh    # full install in a sandbox
│   └── hooks/                  # versioned pre-commit and post-commit hooks (core.hooksPath)
└── docs/adr/                   # architecture decision records
```

## Install on a new Mac

```bash
git clone https://github.com/MathiasDrizzy/dotfiles.git ~/dotfiles
cd ~/dotfiles/mac
./install.sh            # installs packages, links configs, builds herdr-ctl and enables the hooks
exec zsh
```

* `./install.sh --dry-run`: simulates everything and changes nothing.
* `./install.sh --links-only`: only creates directories and symlinks under `$HOME`; it installs no packages, downloads no themes and builds nothing. Useful to try it in a temporary HOME: `HOME=$(mktemp -d) ./install.sh --links-only`.
* `mac/scripts/check-links.sh` checks that `~/.config/...` points into the repo (`--fix` repairs it, keeping a backup).

## herdr shortcuts (`prefix = ctrl+b`)

The complete, current list is in the cheatsheet: **`ctrl+b → h`**. It is generated when opened, from `herdr --default-config` plus `mac/config/herdr/config.toml`, so it cannot list shortcuts that do not exist. Close it with `q` or `Esc`; `/` filters.

What this repo adds on top of herdr's defaults:

| Shortcut | What it does |
|---|---|
| `ctrl+b → ← ↑ ↓ →` | Move focus between panes (replaces `h j k l`) |
| `ctrl+b → Shift+← ↑ ↓ →` | Swap the pane with its neighbor |
| `ctrl+b → h` | Cheatsheet |
| `ctrl+b → t` | Terminal popup (scratchpad); close it with `Esc` (empty prompt), `Ctrl+Q`, `Ctrl+D` or `exit` |
| `ctrl+b → m` | Fit the sidebar width to the screen (`herdr-ctl adapt`) |
| `ctrl+b → f` / `Shift+F` | Sidebar explorer / quick open |
| `ctrl+b → Shift+C` | Move the pane to a new tab |
| `ctrl+b → < / >` | Reorder tabs |
| `ctrl+b → Shift+R` / `Shift+Q` | Refresh agent quotas / their settings (replaces `reload_config`; reload the config with `herdr server reload-config`) |

`herdr-ctl keys-check` compares every shortcut in the repo with herdr's defaults and reports collisions.

## herdr-ctl (Go, `mac/tools/herdr-ctl`)

```bash
herdr-ctl adapt [laptop|external]   # sidebar width: 24 cols (Mac) / 22 cols (ultra-wide monitor)
herdr-ctl cheatsheet                # the ctrl+b → h popup
herdr-ctl keys-check                # shortcut collisions against herdr's defaults
herdr-ctl move-tab new              # move the current pane to a new tab
herdr-ctl status                    # herdr panes over the socket
```

### Agent bus over the herdr socket

A channel to the fallback agent `agy` (and any other agent running in a herdr pane):

```bash
swarm | agents          # swarm status
aprompt <agent> <msg>   # send a prompt to another agent   (herdr-ctl prompt)
aread <agent>           # read its output                  (herdr-ctl read)
afocus <agent>          # jump to its pane                 (herdr-ctl focus)
```

## Aliases (in `mac/zshrc`)

`lg` lazygit · `ld` lazydocker · `sftp` termscp · `hosts` sshs · `y` yazi (leaves the shell in the folder you exit from) · `sb`, `sb-ext`, `sb-lap`, `sb-auto` sidebar · `agy` Antigravity CLI (fallback agent) · `claude` Claude Code (updates itself, then opens in bypass mode; `command claude` skips that) · `brewup`, `brewout` Homebrew.

## Development and testing

```bash
git config core.hooksPath scripts/hooks   # install.sh does this
scripts/harness-quick.sh                  # quick: no local-network data, syntax, go vet/test, keys-check
python3 scripts/harness-behavior.py -v    # opens an isolated herdr and really tests the shortcuts
scripts/test-install-full.sh              # full install in a sandbox with a temporary HOME
```

* The **pre-commit** hook runs the quick harness and, if the commit touches herdr, scripts or `zshrc`, the behavior harness too.
* The **behavior harness** uses a temporary HOME and its own session (it does not touch your herdr). It checks that `prefix+h` opens the cheatsheet and `q`/`Esc` close it, that the terminal popup closes with `Esc`, that `prefix+m` changes the sidebar width, that the arrow keys move focus, that `Shift+arrows` swap panes and that `prefix+Shift+R` runs the repo's command.
* The repo is **public**: no local-network IPs, hostnames, passwords or tokens (the harness enforces it).

## Documentation

* Decisions: [`docs/adr/`](docs/adr/)
* Changes: [`CHANGELOG.md`](CHANGELOG.md)
* Reporting a vulnerability: [`SECURITY.md`](SECURITY.md)

## License

No license has been chosen yet; until one is added, all rights are reserved.
