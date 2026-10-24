# 0001. Keep configs in this repo and symlink them into `$HOME`

* Status: accepted
* Date: 2026-10-11

## Context and problem statement

The terminal setup (Ghostty, herdr, zsh and several TUIs) must be reproducible after reformatting the Mac, and the
files that define it change often. Where should the source of truth live?

## Decision drivers

* One command restores the whole setup on a fresh Mac.
* An edit made while using a tool must not drift away from the versioned copy.
* The installer must be safe to run twice and testable without touching the real `$HOME`.

## Considered options

* Copy the configs into `$HOME` at install time.
* Keep the configs in the repo and symlink them into `$HOME`.
* Use a dotfiles manager (for example chezmoi or GNU Stow).

## Decision outcome

Chosen option: "keep the configs in the repo and symlink them", implemented by `mac/install.sh` and verified by
`mac/scripts/check-links.sh`, because an edit through the link is an edit of the versioned file and no sync step
exists to forget. A dedicated manager would add a dependency to a setup that has to bootstrap itself on a bare Mac.

### Consequences

* Good: no drift between `~/.config/...` and the repo; `git diff` shows every change made through a tool.
* Good: the installer is idempotent and can run with `--links-only` in a temporary `HOME` for tests.
* Bad: a tool that replaces its config file instead of writing through it breaks the link; `check-links.sh --fix`
  repairs it, keeping a backup.
* Bad: the repo is public, so nothing machine-specific or secret may live in these files.

## More information

* `scripts/test-install-full.sh` runs the complete install in a sandbox with a temporary `HOME`.
* `scripts/test-zshenv.sh` proves an existing `~/.zshenv` is backed up and never lost.
