# macOS dotfiles — terminal setup

Terminal configuration for macOS (Apple Silicon): **Ghostty + herdr + zsh + Catppuccin Mocha**, with the everyday TUIs. It is designed to be reinstalled in full after reformatting.

## Layout

```
dotfiles/
├── mac/
│   ├── install.sh              # idempotent installer (--dry-run, --links-only)
│   ├── zshrc / zshenv          # interactive shell and global PATH
│   ├── config/                 # ghostty, herdr, aerospace, yazi, micro, starship, termscp, lazygit, lazydocker, btop, bat
│   ├── scripts/                # check-links.sh, herdr-reload.sh, terminal-popup.sh
│   └── tools/herdr-ctl/        # Go tool: cheatsheet, agent bus, keys-check
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
| `ctrl+b → f` | Open, focus or close the lazyfinder sidebar (it opens by itself, docked on the left of every tab) |
| `ctrl+b → Shift+C` | Move the pane to a new tab |
| `ctrl+b → < / >` | Reorder tabs |

`herdr-ctl keys-check` compares every shortcut in the repo with herdr's defaults and reports collisions.

## AeroSpace (tiling windows, `mac/config/aerospace/aerospace.toml`)

An i3-like tiling window manager that needs no SIP changes. It replaces the native macOS desktops with its own **workspaces** (1 to 9): use a single macOS Space and switch workspaces with the keys below. No vim keys; arrows instead.

| Shortcut | What it does |
|---|---|
| `alt+←↑↓→` | Move focus between windows |
| `alt+shift+←↑↓→` | Move the window in that direction |
| `alt+1…9` | Go to workspace 1…9 |
| `alt+shift+1…9` | Send the window to workspace 1…9 |
| `ctrl+alt+← / →` | Previous / next workspace |
| `alt+tab` | Back to the previous workspace |
| `alt+-` / `alt++` (the keys labelled - and +) | Shrink / grow the window |
| `alt+.` · `alt+,` | Tiles layout · accordion layout |
| `alt+shift+s` | Snail layout for 3 windows: one big on the left, two stacked on the right |
| `alt+shift+space` | Toggle floating / tiling |
| `alt+shift+enter` | Fullscreen |
| `alt+enter` | New Ghostty window |
| `alt+shift+ñ` | Service mode (`esc` reloads the config, `r` resets the layout, `backspace` closes all windows but the current one, `alt+shift+arrows` joins with a neighbor) |

The focused window gets a thin purple round border from [JankyBorders](https://github.com/FelixKratz/JankyBorders) (`borders`, started by AeroSpace; installed by `install.sh`); inactive windows get none.

The keyboard is Latin American, so the punctuation keys are aliased by the symbol printed on them (`key-mapping` in the config). Only numbered workspaces are bound, so the shell's `alt+b/f/d` word motions keep working. It needs the Accessibility permission and `defaults write com.apple.dock expose-group-apps -bool true` so Mission Control shows hidden windows properly.

## SketchyBar (menu bar replacement, `mac/config/sketchybar/`)

A bar of small solid boxes in Catppuccin Macchiato, after [neutonfoo/dotfiles](https://github.com/neutonfoo/dotfiles): a colored icon per box, the Apple menu and the active app as color blocks, JetBrainsMono Nerd Font. The bar itself is transparent so the camera housing stays clear. The native menu bar is set to auto-hide (System Settings → Control Center → *Automatically hide and show the menu bar*: Always).

- Left: Apple menu (click for About, Settings, Sleep, Lock, Log out, Restart, Shut down), the active app (its name in a box of fixed width that slides when the name is longer; click for its menus, centered under it) and the AeroSpace workspaces (only the focused and the occupied ones; click to switch, **drag one onto another to swap their windows**).
- Around the camera notch: the moon phase and the weather (the commune you are in and its temperature) on its left, and the track that is playing on its right (click to play or pause, via [`media-control`](https://github.com/ungive/media-control)).
- Right: Vorssaint (its pill sits right over its hidden menu bar icon, so its menu opens under it), the battery, the date (click for Calendar), the time and a Control Center button. The Control Center button opens the system panel with `fn+C` and closes it again on a second click; while it is open the bar turns into an opaque cover in the color of the desktop so the native bar never shows through.

The weather box finds the commune with [CoreLocationCLI](https://github.com/fulldecent/corelocationcli) (allow it in Location Services) and reads the temperature from Apple Weather, the one the Mac and the iPhone show, through the Shortcuts shortcut *Temperatura barra* (`mac/config/shortcuts/temperatura-barra.plist`). `install.sh` signs it and opens it: click *Add Shortcut*. Without it the box falls back to [Open-Meteo](https://open-meteo.com), which can be a degree off.

`ctlcenter` (a small Swift helper in `mac/tools/ctlcenter`, compiled by `install.sh`, needs the Xcode command line tools) presses `fn+C` and watches the pointer so the workspace drag can start the moment you press. The macOS recording indicator (orange dot) is drawn by the system above everything and cannot be moved or hidden.

AeroSpace starts it and notifies it of workspace changes. Reload after editing: `sketchybar --reload`. Installed by `install.sh`.

The sidebar is [lazyfinder](https://github.com/MathiasDrizzy/lazyfinder) as a herdr plugin (`install.sh` installs it): it docks on the left of each tab and follows the folder of the terminal next to it. Its width, side and auto-open are lazyfinder's own settings (`herdr.width`, `herdr.dock`, `herdr.auto_open`).

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

`lg` lazygit · `ld` lazydocker · `sftp` termscp · `hosts` sshs · `y` yazi (leaves the shell in the folder you exit from) · `sb` lazyfinder sidebar · `agy` Antigravity CLI (fallback agent) · `claude` Claude Code (updates itself, then opens in bypass mode; `command claude` skips that) · `brewup` (non-interactive: no prompts, never asks for a password), `brewout` Homebrew.

## Development and testing

```bash
git config core.hooksPath scripts/hooks   # install.sh does this
scripts/harness-quick.sh                  # quick: no local-network data, syntax, go vet/test, keys-check
python3 scripts/harness-behavior.py -v    # opens an isolated herdr and really tests the shortcuts
scripts/test-install-full.sh              # full install in a sandbox with a temporary HOME
```

* The **pre-commit** hook runs the quick harness and, if the commit touches herdr, scripts or `zshrc`, the behavior harness too.
* The **behavior harness** uses a temporary HOME and its own session (it does not touch your herdr). It checks that `prefix+h` opens the cheatsheet and `q`/`Esc` close it, that the terminal popup closes with `Esc`, that `prefix+f` runs the lazyfinder plugin's toggle action, that the arrow keys move focus, that `Shift+arrows` swap panes and that `prefix+Shift+R` stays herdr's own `reload_config`.
* The repo is **public**: no local-network IPs, hostnames, passwords or tokens (the harness enforces it).

## Documentation

* Decisions: [`docs/adr/`](docs/adr/)
* Changes: [`CHANGELOG.md`](CHANGELOG.md)
* Reporting a vulnerability: [`SECURITY.md`](SECURITY.md)

## License

Released under the [MIT License](LICENSE).
