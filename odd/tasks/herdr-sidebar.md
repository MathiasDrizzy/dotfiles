# herdr sidebar: useful spaces and agents rows

Objective: the herdr sidebar shows real, useful data per space and per agent. Branch: feat/swift-bar (pushed to main
in reviewed slices). Delivery: single PR-sized slices on main. Test runner: `go test ./...` in mac/tools/herdr-ctl.

## Specs

- S1 Spaces take 2 lines, agents 3, as the user drew it:
  ```
  spaces
  ✱ Config mac
    feat/swift-bar ↑2 ✚3 · CI ✓

    agents
    ✱ dotfiles   opus 5.5
     trabajando  ctx 62%
      5h 34% · sem 61%
  ```
- S2 The data is real: the 5-hour and weekly usage match Claude's `/usage` ("osea no es 34% es 51%"), the context is
  the session's own, the model is the session's model.
- S3 Spaces show the commits not pushed (`↑`), the changed files (`✚`) and the last CI run of the branch (`CI ✓/✗`).
- S4 "yo lo quiero en herdr no en la barra": the 5h/weekly usage lives in herdr's agent rows, not in dotbar.

## Tasks

- T1 S1-S4 herdr-ctl `statusline` (Claude Code status line: publishes model, context, usage and state labels to the
  agent's pane) and `spaces-sync` (launch agent every minute: ahead, changed files, CI per space; usage to every
  agent), herdr config rows, install.sh agent, settings.json statusLine, docs. Route: inline (one unit, no parallel
  reason). Status: done; go test (race), go-checks, check-repo, lint, test-install-full PASS.

## Log

- L1 (2026-10-26, user, verbatim): "bien ahora quiero cambiar esto [Image #20] de herdr que es los space y los agents,
  no me gusta como se ve, 1. quitan mucho espacio y segundo no se como leerlos, dime ideas de como podemos modificarlo,
  para que se vea mejor y sea de ayuda"
- L2 (verbatim): "vamos bien, puedo tener en agentes, tambien el porcentaje usado de las horas y de la semana?";
  "pero eliminaste lo del ci y lo del % de 5 horas y semanal yo lo quiero en herdr no en la barra"; "no asi noo: seria"
  with the layout in S1; "se ve pero no es real ... osea no es 34% es 51% y el contexto no se si es real".
- L3 Facts checked: herdr 0.9.5 rows accept `$name` tokens reported with `herdr pane|workspace report-metadata <id>
  --source <s> --token k=v` (the id goes first); reports merge, the last value of a token wins; `--state-label
  STATUS=TEXT` renames a state. Claude Code's status line JSON carries `model.display_name`,
  `context_window.used_percentage` and, for Pro/Max after the first response, `rate_limits.five_hour|seven_day
  .used_percentage|resets_at`; `statusLine.refreshInterval` re-runs it while idle.
- L4 (2026-10-26, user, verbatim): "recuerda revisar que no haga bug o bucle en el cual gaste mucha cpu o ram, como nos
  paso con nuestro incidente, recuerda hacerlo en tiempo real para que siempre sepa lo que esta pasando con el contexto
  y los tokens". Every outside command has a limit (herdr 2 s, git 5 s, gh 15 s; tested with a hung `sleep`).
  Measured: statusline 0.01 s, 9 MB; spaces-sync 1.8 s wall (GitHub), 0.25 s CPU, 46 MB peak, then exits; launchd never
  overlaps two passes. Real time: Claude refreshes the status line on every update and every 30 s (refreshInterval).
- L5 (2026-10-26, user, verbatim): "revisa ahora lo del arbol en space, ahora cambie y tengo un space llamado Desarrollo
  Tuis, donde tengo a Lazymark y Lazyfinder y solo veo 1 main ... yo quiero que me diga el nombre de completo de la ruta
  de la barra no la rama ... deberia aparecer solo dotfiles y si abro otra cosa ya sea micro lazy finder etc, deberia
  decir por ejemplo dotfiles > micro. cuando ejecutas herdr ctl siempre me pide permitir, dale permisos para siempre".
  Spaces now list each repository of their panes ($repo1..3 with $repo1s..3s; a tree with names when there are
  several; herdr hides empty rows, checked in its src/ui/sidebar/tokens.rs). Tabs: Auto Title's
  HERDR_AUTO_TITLE_BRANCH_MAX=0 (mac/config/herdr-auto-title/config.env, linked) gives `dotfiles`, and a background
  test tab with micro read `dotfiles › micro`. herdr-ctl was signed ad hoc as `a.out`, so every build looked new to
  macOS; it is now signed with the local certificate as dev.dotfiles.herdr-ctl (install.sh too). No tccd entry named
  it, so the exact prompt the user saw is not confirmed.
- L6 (2026-10-26, user, verbatim): "hay algunas que no se actualizan por ejemplo lazymark ... como que aveces se
  actualizan y aveces no, es claude y solo el que esta trabajando esta actualizado el -> 19:00 que pone la hora me
  gusta pero a veces no va y no aparece"; then "es muy grande, no puede aparecer main y CI con su visto, en una segunda
  linea? tipo abajo del nombre." Cause: idle sessions re-run the status line every 30 s with their own last
  response's usage, and the newest reading was chosen by when it arrived. Now newestLimits compares the data (later
  5-hour window, else more used) and every session shows the merged newest; live, the three agents held
  `5h 88% →19:00 · sem 65%` for 75 s. The tree puts each name on its own row and branch and state below it (a braille
  blank keeps the last branch indented: herdr trims leading spaces).
