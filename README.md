# macOS dotfiles — terminal setup

Terminal configuration for macOS (Apple Silicon): **Ghostty + herdr + zsh + Catppuccin Mocha**, with the everyday TUIs. It is designed to be reinstalled in full after reformatting.

## Layout

```
dotfiles/
├── mac/
│   ├── install.sh              # idempotent installer (--dry-run, --links-only)
│   ├── zshrc / zshenv          # interactive shell and global PATH
│   ├── config/                 # ghostty, herdr, aerospace, micro, starship, termscp, lazygit, lazydocker, btop, bat
│   ├── scripts/                # check-links.sh, herdr-reload.sh, terminal-popup.sh
│   └── tools/herdr-ctl/        # Go tool: cheatsheet, agent bus, keys-check
├── scripts/
│   ├── check-repo.sh           # public-repo hygiene, syntax, modes, TOML, config tests
│   ├── go-checks.sh            # herdr-ctl: vet, test -race, golangci-lint, govulncheck
│   ├── lint-shell.sh           # shellcheck and shfmt
│   └── test-install-full.sh    # full install in a sandbox
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
| `ctrl+b → f` | Open, focus or close the lazyfinder sidebar (it opens by itself, docked on the left of every tab) |
| `ctrl+b → Shift+C` | Move the pane to a new tab |
| `ctrl+b → < / >` | Reorder tabs |

`herdr-ctl keys-check` compares every shortcut in the repo with herdr's defaults and reports collisions.

## AeroSpace (tiling windows, `mac/config/aerospace/aerospace.toml`)

An i3-like tiling window manager that needs no SIP changes. It replaces the native macOS desktops with its own **workspaces** (1 to 9 on the Mac, and another 1 to 9 on the external monitor): use a single macOS Space and switch workspaces with the keys below. No vim keys; arrows instead.

| Shortcut | What it does |
|---|---|
| `alt+←↑↓→` | Move focus between windows |
| `alt+shift+←↑↓→` | Move the window in that direction |
| `alt+1…9` | Go to workspace 1…9 |
| `alt+shift+1…9` | Send the window to workspace 1…9 |
| `ctrl+alt+1…9` | Go to the external monitor's workspace 1…9 (named `e1…e9` in the config, drawn as 1…9 in the blue pill) |
| `ctrl+alt+shift+1…9` | Send the window to the external monitor's workspace 1…9 |
| `ctrl+alt+← / →` | Previous / next workspace |
| `alt+tab` | Back to the previous workspace |
| `alt+-` / `alt++` (the keys labelled - and +) | Shrink / grow the window |
| `alt+.` · `alt+,` | Tiles layout · accordion layout |
| `alt+shift+s` | Snail layout for 3 windows: one big on the left, two stacked on the right |
| `alt+shift+space` | Toggle floating / tiling |
| `alt+shift+enter` | Fullscreen |
| `alt+enter` | New Ghostty window |
| `alt+shift+ñ` | Service mode (`esc` reloads the config, `r` resets the layout, `backspace` closes all windows but the current one, `alt+shift+arrows` joins with a neighbor) |

The focused window gets a thin purple round border from [JankyBorders](https://github.com/FelixKratz/JankyBorders) (`borders`, started by AeroSpace; installed by `install.sh`); inactive windows get none. It is drawn above the window (`order=above`), so an app's own edges never cover it.

The keyboard is Latin American, so the punctuation keys are aliased by the symbol printed on them (`key-mapping` in the config). Only numbered workspaces are bound, so the shell's `alt+b/f/d` word motions keep working. It needs the Accessibility permission and `defaults write com.apple.dock expose-group-apps -bool true` so Mission Control shows hidden windows properly.

## dotbar (menu bar replacement, `mac/tools/dotbar/`)

The bar is one native Swift app: a panel above the menu bar on every Space that never takes the focus. It keeps its state
in memory and follows the system through events and long-lived streams (AeroSpace's `subscribe`, `media-control
stream`, IOKit, the network path, NSWorkspace); it starts no process per tick, and every outside command it runs has a
time limit and never runs twice at once. A bar of small solid boxes in Catppuccin Macchiato, after
[neutonfoo/dotfiles](https://github.com/neutonfoo/dotfiles): a colored icon per box, the Apple menu and the active app
as color blocks, JetBrainsMono Nerd Font. The native menu bar is set to auto-hide (System Settings → Control Center →
*Automatically hide and show the menu bar*: Always).

- Left: Apple menu (click for About, Settings, Sleep, Lock, Log out, Restart, Shut down), the active app (its name in a box of fixed width that slides when the name is longer; click for its menus) and the AeroSpace workspaces (only the focused, the visible and the occupied ones; click to switch, **drag one onto another to swap their windows**). With an external monitor connected, its workspaces get a pill of their own, marked with a monitor glyph and in blue.
- Nothing covers anything: the camera housing and the neighbouring boxes are hard stops. When the left side runs out of room, the front app name narrows first, then workspaces leave (the pill says `+N`); the track is cut to stop short of Vorssaint.
- Around the camera notch: the moon phase and the weather (the commune you are in and its temperature) on its left, and the track that is playing on its right (click to play or pause, via [`media-control`](https://github.com/ungive/media-control)).
- Right: Vorssaint (its box sits over its hidden menu bar icon, so its menu opens under it), the battery, the date (click for Calendar), the time and a Control Center button (`fn+C`, a second click closes it). While a panel or menu is open, the bar draws the wallpaper behind its boxes so the native bar never shows through.
- When the last window of a workspace closes, the focus stays there instead of following macOS to another app's workspace.

The weather is native: the commune from Location Services (CoreLocation and its reverse geocoding), the temperature from [Open-Meteo](https://open-meteo.com) (Apple Weather needs a paid developer account), every 30 minutes and on wake.

`install.sh` builds it into `~/Applications/dotbar.app` and starts it at login with a launch agent (`~/Library/LaunchAgents/dev.dotfiles.dotbar.plist`, started again if it crashes). Its first run asks for Location; grant Accessibility to `dotbar` in System Settings for the app menus, Control Center and Vorssaint. It also keeps AeroSpace in place when the app in front quits (its own `aerospace subscribe` helper plus `ctlcenter stay` from `mac/tools/ctlcenter`); with an AeroSpace that supports `stay-on-workspace-when-app-quits`, turn both off with `defaults write dev.dotfiles.dotbar stay -bool false`. Rebuild after editing: `mac/tools/dotbar/scripts/bundle.sh ~/Applications`, then `launchctl kickstart -k gui/$(id -u)/dev.dotfiles.dotbar`. Checks: `cd mac/tools/dotbar && swift run dotbar-tests`.

Tabs are named after what runs in them by the [Auto Title](https://github.com/kryptamine/herdr-auto-title) herdr plugin (`install.sh` installs it, pinned to a release; it needs `ui.prompt_new_tab_name = false`, already set). A tab you rename by hand keeps its name.

The sidebar is [lazyfinder](https://github.com/MathiasDrizzy/lazyfinder) as a herdr plugin (`install.sh` installs it): it docks on the left of each tab and follows the folder of the terminal next to it. Its width, side and auto-open are lazyfinder's own settings (`herdr.width`, `herdr.dock`, `herdr.auto_open`).

herdr's own sidebar shows two lines per space and three per agent:

```
spaces
✱ Config mac
  feat/swift-bar · ↑2 ✚3 · CI ✓
○ Desarrollo Tuis
  ├ lazymark
  │ main · CI ✓
  └ lazyfinder
    main · ✚1

agents
✱ dotfiles · opus 5.5
  trabajando · ctx 62%
  5h 51% · sem 61%
```

A space shows, for each repository its panes are in (as a tree when there are several, up to three: each name on a line, its branch and state on the next), its branch, the commits not pushed (`↑`), the files changed (`✚`) and the branch's last CI run (`✓` passed, `✗` failed, `…` running). An agent shows its model, its state, the context it has used, and the account's 5-hour and weekly usage, the same numbers as Claude's `/usage` (every session reports what its own last response saw, so the newest reading wins: the later 5-hour window, or more used in the same one); a window at 75% or more also shows when it comes back. `herdr-ctl statusline` is Claude Code's status line (`"statusLine": {"type": "command", "command": "$HOME/.local/bin/herdr-ctl statusline", "refreshInterval": 30}` in `~/.claude/settings.json`): it reports each session's model, context and usage to its herdr pane. `herdr-ctl spaces-sync`, run every minute by the `dev.dotfiles.herdr-spaces` launch agent that `install.sh` loads, reports each space's git and CI state and hands the newest usage to every agent.

## herdr-ctl (Go, `mac/tools/herdr-ctl`)

```bash
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

`lg` lazygit · `ld` lazydocker · `sftp` termscp · `hosts` sshs · `lazyfinder` (leaves the shell in the folder you exit from) · `sb` lazyfinder sidebar · `agy` Antigravity CLI (fallback agent) · `brewup` (non-interactive: no prompts, never asks for a password), `brewout` Homebrew.

## Development and testing

```bash
scripts/check-repo.sh                     # public-repo hygiene, script syntax and modes, TOML, config tests
scripts/lint-shell.sh                     # shellcheck and shfmt
scripts/go-checks.sh                      # herdr-ctl: vet, test -race, golangci-lint, govulncheck
scripts/test-install-full.sh              # full install in a sandbox with a temporary HOME
(cd mac/tools/dotbar && swift run dotbar-tests)  # the bar's checks (workspaces, runner, fit, weather, media, swap...)
```

* Development runs under the gentle-ai harness (ODD workflow, Engram memory, CodeGraph); the repo keeps no git hooks of its own.
* The repo is **public**: no local-network IPs, hostnames, passwords, tokens or precise coordinates (fixtures use Plaza de Armas, `-33.437800, -70.650500`); `scripts/check-repo.sh` checks it in CI.
* CI runs every check above on each push to `main`. Push reviewed work often: gentle-ai reviews the commits not yet on `origin/main`, and a long unpushed range outgrows its review budget.

## Documentation

* Decisions: [`docs/adr/`](docs/adr/)
* Changes: [`CHANGELOG.md`](CHANGELOG.md)
* Reporting a vulnerability: [`SECURITY.md`](SECURITY.md)

## License

Released under the [MIT License](LICENSE).
