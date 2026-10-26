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
- S4. SketchyBar keeps running until dotbar reaches parity; then it is removed: "al tenerla al 100% vamos a borrar
  sketchybar" (launch at login, SketchyBar and its config and plugins deleted, installer, docs) as the last task.
- S6. "recuerda hacer la barra con la misma estetica": the same look as today's bar, box by box (sizes, colors, fonts,
  glyphs, gaps, radii), checked side by side by screenshot.
- S7. "el clima y hora como lo estas haciendo con swift si lo puedes hacer nativo en vez de hacer hooks o automatizaciones
  como lo tenemos hazlo": the weather, the place and the time come from native APIs (no Shortcuts shortcut, no
  CoreLocationCLI, no curl).
- S5. Every task ships with its tests (unit tests for the logic; a visual check by screenshot for drawing) and passes
  the existing repo checks.

## Tasks

| ID | Specs | Route | Status | Commit |
|----|-------|-------|--------|--------|
| T1 | S2, S5 | inline | done | f5785b7 |
| T2 | S3 workspaces, S2, S6 | inline | done | ff98d3e |
| T3 | S3 front app, Apple menu | delegated | done | bb77619 |
| T4 | S3 battery, date, time, network; S7 | inline | done | 2423141 |
| T5 | S3 weather, moon; S7 | delegated | done | 8118f3f |
| T6 | S3 now playing | delegated | done | fde7e9e |
| T7 | S3 notch fit, other monitor, the "+N" cap | inline | done | aeae6b4 |
| T8 | S3 Control Center, cover, Vorssaint, drag to swap | delegated | done | 4fb3413, 7923ddf, 34c8aca |
| T9 | S4 switch and SketchyBar removal | inline | done | 7052e8d |

- T1: Swift package `mac/tools/dotbar` (library + app + tests); a non-activating panel above the menu bar on the main
  display, transparent, 40 pt tall, full width; a development flag to draw it at the bottom next to SketchyBar; the
  time-limited command runner of S2 with tests.
- T2: AeroSpace from its `subscribe` stream (no polling); pills and their states; click. The "+N" cap is computed in the
  core but drawn from T7, which measures the room it depends on.
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
- L5 (2026-10-25, user, verbatim): "recuerda hacer la barra con la misma estetica, al tenerla al 100% vamos a borrar
  sketchybar." S4 now ends with SketchyBar removed, and S6 pins the same look.
- L6: T2 done. AeroSpace's `subscribe` stream (one process for the bar's life) drives the pills; a switch is painted from
  the event, then the workspaces are read again (one read at a time, one more if events came meanwhile), plus a 5 s
  fallback for windows closed elsewhere. 25 checks pass (layout ported from aerospace.sh: occupied, visible, the other
  monitor, unplugged monitor, the cap; event parsing; the stream reads lines, restarts, stays stopped). Live, side by
  side with SketchyBar: same sizes, colors and font; a switch shows within 250 ms; after 24 switches 120 ms apart the
  focus drawn is the real one, 0.4% CPU, one child process. Quitting (SIGTERM) stops the stream: nothing is left.
  Next step: T3 (Apple menu and front app).
- L7: Native review of T1-T2 approved with warnings, all fixed: the runner waits on dispatch threads, never on Swift's
  cooperative ones; output is read by a handler (no thread blocked on a pipe a leftover child holds open; no unlocked
  access); on its limit the command and every process below it end; the stream runs one process whatever the order of
  start, stop and its end; a look at the workspaces that started before a switch is dropped (WorkspaceState). The "+N"
  cap moved to T7 (the review found it was never drawn). The rc bracket check stays unanchored: live counts matched
  (19 = 19, 20 = 20). 33 checks pass; live burst ends on the real focus, 0.4% CPU, one child; nothing left on quit.
- L8 (2026-10-25, user, verbatim): "el clima y hora como lo estas haciendo con swift si lo puedes hacer nativo en vez de
  hacer hooks o automatizaciones como lo tenemos hazlo" -> S7, for T4 and T5.
- L9 (2026-10-25, user, verbatim): "no tengo apple developer de pago" -> the temperature comes from Open-Meteo through
  URLSession (WeatherKit needs a paid account); the place from CoreLocation and CLGeocoder.
- L10: T4 done. Clock and date redraw when the minute changes (and on wake); battery from IOKit's power source
  notification; network from NWPathMonitor; no process, no polling. Side by side with SketchyBar: same boxes (71, 108,
  65, 28 points), glyphs, colors and labels. Two Command Line Tools limits found: SwiftUI's @State is a macro whose
  plugin ships only with Xcode (view state lives in @Observable models; Hover keeps the box under the pointer), and
  SwiftUI cuts a Nerd glyph at its character's edge (NerdIcon draws it whole). Checks split per area: Support.swift,
  CoreTests.swift, one function per area called from main.swift. 46 checks pass.
- L11 (2026-10-25, user, verbatim): "hazlo todo, procesede a hacer todos los pasos , ocupa sub agentes, gentle-ai,
  codegraph, context7 etc.. todo lo que tengas en tu alcance" -> T3, T5 and T6 go to three writers in parallel, each in
  its own worktree (they build Swift; one tree would lock); the parent merges, wires the bar and does T7-T9.
- L12: T3, T5 and T6 delivered by parallel writers and merged into feat/swift-bar (6efecc5, 95994e2 and the T3 merge);
  all checks pass together. Open items for the parent: T7 places moon/weather left of the notch and media right of it,
  the "+N" cap, and a bar-wide 1 point text offset (SwiftUI centers text higher than SketchyBar; T3 nudged its own
  boxes); Control Center icon may use T3's AppGlyph; the user grants Location (dotbar.app first launch) and
  Accessibility (first click on the front app pill) once. Not exercised live: app-menus popup, long-name slide,
  session actions, permission dialogs. Next step: T7, then T8, T9.
- L13: Native review of the merged T3/T5/T6 approved with warnings, fixed in 3086c72 (when-in-use location counts:
  on macOS it reads as raw value 3; menu reads have a 3 s overall limit; floods capped at 1 MB and 64 KB per read; the
  track never runs one over; Open-Meteo gets the place to two decimals). T7 done: BarFit ports fit.sh (the 224 point
  gap around the housing, 623-847 on the MacBook; the name narrows to 40 then workspaces leave with "+N"; the track gets
  (Vorssaint - 5 - housing - 70) / 7.2 characters, 8 to 35). The weather box reports its measured width; the bar is
  two zones around the housing. Side by side with SketchyBar the boxes line up; Vorssaint is T8.
- L14: T8 done by three writers and merged: Control Center click and the cover (4fb3413: fn+C posted natively, the
  controlcenter.sh driver in DotbarCore, the cover is the wallpaper strip from desktopImageURL, no Screen Recording),
  Vorssaint (7923ddf: the menu extra pressed through Accessibility, closed with a click outside, the battery, date and
  time boxes widen so Vorssaint sits over its extra), drag to swap (34c8aca: ghost pill, tints, glide, the swap plan
  through time-limited aerospace calls, refreshes skipped meanwhile). stay.sh's rule (9652da3, 873a205) is wired: a
  pill click marks a switch as asked, a swap pauses it; Vorssaint's popover holds the cover. 254 checks pass. Live, the
  integrated bar matches SketchyBar box by box (only the temperature source differs), 0% CPU, 57 MB, two aerospace
  streams and one media stream as children, nothing left after quit. Next step: T9.
- L15: T9 done in the repo: install.sh builds dotbar.app into ~/Applications (scripts/bundle.sh, build under
  ~/.cache/dotbar-build) and loads the launch agent dev.dotfiles.dotbar (written with printf: macOS's bash keeps a
  here-document in a temporary file the installer test's sandbox forbids), uninstalls SketchyBar and removes its links;
  AeroSpace no longer calls SketchyBar; mac/config/sketchybar, the Shortcuts weather shortcut and the five SketchyBar
  tests are gone; dotbar starts `ctlcenter stay`. The installer test stubs `swift` (SwiftPM cannot build inside its
  sandbox: it uses the real user's caches and a build service that cannot write there); the real build is covered by
  bundle.sh and dotbar-tests. Full install test: PASS.
- L16 (2026-10-26, user, verbatim): "sigue con el proceso pero desactiva sketchybar para mi y deja la barra de mac
  nativa, la de sketchybar no funciona esta pegada. recuerda ver si por ejemplo ahora que usamos switft podemos poner
  nativamente los botones de vorssaint o la barra de mission control. temina lo que estamas haciendo." Done on this Mac:
  SketchyBar and its helpers stopped, menu bar auto-hide off (the native bar shows). dotbar is not installed on this
  Mac yet: the user keeps the native bar until they ask for dotbar.
- L17 (2026-10-26, user, verbatim): "no esta centrado vorssaint,revisa bien el tema de los permisos que se le den los
  permisos necesarios y para siempre a la barra aunque se reinicie, borra sketchybar esta mucho mejor y perfecta que
  esa". dotbar installed on this Mac; the planet is centered by its ink (InkCenteredIcon); bundle.sh signs with a local
  self-signed certificate (scripts/signing-identity.sh) so the permissions survive rebuilds; SketchyBar uninstalled.
- L18 (2026-10-26, user, verbatim): "dale soluciona lo que tengas que solucionar, borra lo que tienes que borrar para no
  dejar redundancia de procesos, revisa que pruebas hiciste y si dejaste procesos abiertos o procesos que esten dos
  veces". AeroSpace now runs the patched fork build (PR nikitabobko/AeroSpace#2352) with
  `stay-on-workspace-when-app-quits = true`, so the `stay` default now turns off both dotbar helpers (its subscribe
  stream and `ctlcenter stay`); JankyBorders is commented out of aerospace.toml. dotbar-tests PASS; one AeroSpace, one
  dotbar and one subscribe stream remain.
- L19 (2026-10-26, user, verbatim): "la pildora del tiempo se podra cambiar el emogi? tipo en vez de utilizar un
  termostato utilizar emogis de si esta lloviendo, si esta soleado, si esta nublado etc.." then "si dale, hazlo con los
  íconos de la fuente". The weather box reads Open-Meteo's weather_code and is_day in the same request and draws the
  Nerd Font's weather-icons glyph in pink (thermometer until a sky is known). The moon box was checked: today's age is
  15.1 days, so the full moon it shows is right. dotbar-tests PASS; checked live (overcast: a cloud).
- L20 (2026-10-26, user, verbatim): "se ve cortado el emogi". The weather-icons glyphs' ink is up to 20 points wide but
  their advance is 11 at 19 points, so they ran into the label and were cut; SkyIcon draws each in a fixed 20-point
  slot centered by its ink. Checked live (overcast: the whole cloud shows); dotbar-tests PASS.
- L21 (2026-10-26, user, verbatim): "conecte el monitor externo y mira el icono no aparece completo". The other
  monitor's mark (nf-md-monitor, ink 13.8 points against a 9-point advance) was cut like the sky glyph; it is drawn
  with InkCenteredIcon in its slot. Checked live with the MSI monitor connected; dotbar-tests PASS.
