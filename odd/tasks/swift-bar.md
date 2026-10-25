# Swift bar (dotbar)

Objective: replace SketchyBar and its bash plugins with one native Swift app (`dotbar`) that draws the same bar, so no
plugin process is ever spawned per tick. Branch `feat/swift-bar`; delivery `ask-on-risk`; tests with `swift run dotbar-tests` (in mac/tools/dotbar).

## Specs

- S1. The user's request, verbatim: "prefiero que sea swift al 100%" (answering which way to replace SketchyBar, after
  "averigua cual es el mejor lenguaje para mac para hacer una barra como esta, ya que sketchybar nos esta dando muchos
  problemas quizas es mejor realizarlo con lenguajes de programacion nativos para que sea mas concistente y no falle").
- S2. One long-lived process: state lives in memory; outside data comes from system APIs or long-lived streams; any
  outside command it must run has a time limit and is never started again while one is still running.
- S3. Same bar as today (parity with mac/config/sketchybar): the layout, boxes, colors (Catppuccin Macchiato), fonts
  (JetBrains Mono Nerd Font) and glyphs; left: Apple menu, front app (icon and name sliding when long), AeroSpace
  workspaces (focused, visible, occupied; the other monitor's pill; "+N" when they do not fit; click to switch, drag to
  swap); left of the notch: moon phase, weather (commune and temperature); right of the notch: now playing (Spotify);
  right: Vorssaint, battery, date, time, Control Center; the cover that keeps the native menu bar hidden; nothing ever
  overlaps another box or the camera housing.
- S4. SketchyBar keeps running until dotbar reaches parity; the switch (launch at login, SketchyBar off, installer,
  docs) is the last task. Assumption: the user wants the switch only at parity.
- S5. Every task ships with its tests (unit tests for the logic; a visual check by screenshot for drawing) and passes
  the existing repo checks.

## Tasks

| ID | Specs | Route | Status | Commit |
|----|-------|-------|--------|--------|
| T1 | S2, S5 | inline | done | feat(dotbar) T1 commit |
| T2 | S3 workspaces, S2 | inline | pending | |
| T3 | S3 front app, Apple menu | inline | pending | |
| T4 | S3 battery, date, time, network | inline | pending | |
| T5 | S3 weather, moon | inline | pending | |
| T6 | S3 now playing | inline | pending | |
| T7 | S3 notch fit, other monitor | inline | pending | |
| T8 | S3 Control Center, cover, Vorssaint, drag to swap | inline | pending | |
| T9 | S4 switch | inline | pending | |

- T1: Swift package `mac/tools/dotbar` (library + app + tests); a non-activating panel above the menu bar on the main
  display, transparent, 40 pt tall, full width; a development flag to draw it at the bottom next to SketchyBar; the
  time-limited command runner of S2 with tests.
- T2: AeroSpace from its `subscribe` stream (no polling); pills and their states; click; the "+N" cap.
- T3-T8: one area of S3 each, ported from the matching plugin.
- T9: launch agent, SketchyBar disabled, install.sh and its test, README.

## Log

- L1 (2026-10-25, user, verbatim): "prefiero que sea swift al 100%"
- L2: Context. The week's failures came from the bash plugin model (a process per tick, hung outside commands piling
  up, races between scripts, a missing link), not from SketchyBar's C core. The user chose a full Swift rewrite over
  keeping SketchyBar with one long-lived helper. Toolchain: Swift 6.4, Command Line Tools only (no Xcode), macOS 27.
- L3: `swift test` fails with the Command Line Tools alone (the Testing framework does not build without Xcode), so the
  checks are an executable target: `swift run dotbar-tests`, exit status 1 on any failure.
- L4: T1 done. 10 checks pass (bar frame on top, bottom and a second screen; command output; missing command; a hung
  command ended by its limit with nothing left running; five callers sharing one process; the key free again after).
  Visual check: the panel drew its box over the front window at the bottom, the app in front stayed in front, 0% CPU
  and about 45 MB idle. Next step: T2 (AeroSpace workspaces from its subscribe stream).
