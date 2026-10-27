# dotbar: agent instructions

You maintain `dotbar`, a Swift menu-bar app for macOS. Read `README.md` first.

## Layout

- `Sources/DotbarCore`: pure logic, no AppKit. Everything testable lives here.
- `Sources/dotbar`: the AppKit shell (items, windows, timers). Keep it thin.
- `Sources/dotbar-tests`: the test runner (`swift run dotbar-tests`, no XCTest needed).
- `scripts/bundle.sh`, `scripts/signing-identity.sh`: build the `.app` and sign it with a stable local certificate so macOS privacy permissions (TCC) survive rebuilds. Ad hoc signing makes every build look like a new program.

## Hard-won facts

- Nerd Font glyphs: center the ink, not the advance (`InkCenteredIcon`), or icons look off by a pixel.
- No public API puts the Mac to sleep or opens Control Center for a user process: the code drives them with bounded helpers (see `ControlCenter.swift`), one driver at a time.
- Idle cost is the metric: timers must be coalesced, work off the main thread, and every outside command has a timeout.
- Test before you trust a visual change: record the screen (`screencapture -v`) and analyze frames; do not eyeball.

## Checks

`swift run dotbar-tests` must pass; CI also builds the release product.

## Rules for every change

- Conventional Commits (`feat(scope): ...`), one reviewable unit per commit with its tests and docs. No AI attribution or `Co-Authored-By` lines.
- Artifacts (code, comments, docs, commit messages) are in English; the maintainer talks to you in Spanish.
- This repository is public: never commit secrets, tokens, IPs of a private network, or precise personal coordinates.
- Nothing hardcoded to one machine, repository, space or agent name: it must work for anyone.
- Cost matters more than features: keep idle CPU near zero and RAM small. Prefer events over polling; any polling needs a stated reason and a measured cost. Never leave a background process looping, hung or forgotten.
- Work on a branch, push it as `ci/<name>` to run CI, merge to `main` only when green. Do not push to `main` untested.
- The `dotfiles` repository pins this one as a submodule (`mac/tools/<name>`); after merging here, bump the pointer there.
