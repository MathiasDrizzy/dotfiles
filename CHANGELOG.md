# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/), and this project intends to
follow [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html) once it has tagged releases.

## [Unreleased]

### Added
- macOS terminal setup: Ghostty, herdr, zsh and the everyday TUIs (yazi, micro, starship, termscp, lazygit,
  lazydocker, btop, bat) with the Catppuccin Mocha theme, kept as versioned configs and linked into `$HOME`.
- Idempotent installer `mac/install.sh` with `--dry-run` and `--links-only`, and `mac/scripts/check-links.sh` to
  verify (and repair) the links.
- `herdr-ctl`, a small Go tool: shortcut cheatsheet generated from herdr's defaults plus this repo's overrides,
  sidebar width adaptation, shortcut-collision check (`keys-check`) and an agent bus over herdr's socket.
- A `claude` shell function that updates Claude Code before opening it and starts it in bypass mode.
- Test harness: a quick check run by the pre-commit hook, a behavior test that drives a sandboxed herdr, and a
  full-install test that runs in a sandbox with canaries.
- Security policy, editor settings, architecture decision records and this changelog.
- MIT license.
- `golangci-lint` v2, `govulncheck` and race-detector tests for `herdr-ctl`, with pinned tool versions, plus Dependabot for its Go modules.
- Continuous integration on GitHub Actions (macOS): repo checks, `shellcheck` and `shfmt`, with Dependabot for the actions.

### Changed
- The README is now in English.
- Ghostty uses `background-blur` and no longer extends the padding color.

### Fixed
- `~/.zshenv` is no longer lost on install and keeps `~/.local/bin` on the non-interactive `PATH`.
