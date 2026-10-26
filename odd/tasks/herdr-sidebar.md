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
- L7 (2026-10-26, user, verbatim): "y el que esta solo? aparece raro, no sera mejor dejarlo tambien como esta
  desarrollo de tuis, osea con su arbol aunque sea solo, para seguir una linea". A space with one repository is now a
  tree of one (`└ dotfiles`, its branch and state below), the same shape as a space with several.
- L8 (2026-10-26, user, verbatim): "recuerda que esto deber hacerlo general para todos, no harcodees nombres." and
  "como que la linea no es continua poque? se ve raro asi que sea continua del mismo color". Checked: no repository,
  space or agent name is written in the code; they come from git's top level, herdr and Claude. herdr joins a row's
  tokens with " · " (src/ui/sidebar/tokens.rs `separator`), so the tree line cannot be a token of its own: both the
  name and branch rows are dimmed and the line is one color.
- L9 (2026-10-26, user, verbatim): "me quede sin toquens y aparce libre y no es asi deberia haber un estado diciendo que
  estoy sin tokens po algo" and "cuando se cierra una tab, se demora mucho en actualizar que ya no esta ese agente".
  Idle agents read "sin tokens" while the 5-hour or weekly window is at 100% and has not reset (labelsFor; spaces
  passes refresh the labels, so they come back on their own). The minute's spaces-sync became `spaces-watch`, kept
  alive by launchd (KeepAlive, ThrottleInterval 10): it subscribes to herdr's structural events only (never metadata
  or *.updated, which its own reports raise: tested, the loop lazyfinder once had), settles bursts for 0.4 s, skips
  reports that change nothing, asks gh at most once a minute per branch, and reconnects after 5 s doubling to 60 s.
  Measured: a tab with another repository showed in the tree in 2.1 s and left it 1.65 s after closing (was up to
  60 s); idle, 0.09 s CPU a minute and 11 MB.
- L10 (2026-10-26): the lazyfinder agent reported (for the user) that a Claude pane in the lazyfinder repo was labeled
  "lazyfinder", the label its plugin finds the sidebar by, so `toggle` closed the user's tab three times; the user then
  showed a sidebar labeled "lazymark › lazyfinder". Both came from Auto Title naming panes: HERDR_AUTO_TITLE_PANES=false,
  the Claude pane's label cleared; the mislabeled sidebar (wF:p8) left to the lazyfinder side as asked. The review of
  9374d25 (approved) warned that a subscription herdr drops at once was retried with no wait: every disconnect now
  waits, doubling, and only a connection that held a minute starts over; CI is kept 55 s (under the minute's pass);
  reports for closed panes and spaces are forgotten.
- L11 (2026-10-26, user, verbatim): "en herdr hay como un fondo de color cuando seleccionas space, que se confunde porque
  no se ve ademas es cuadrado y feo, se podra eliminar y dejar otra cosa como selector?" `active_row_bg = "reset"`
  removes the filled block behind the active space; the active space stays the bold bright one. selection_bg (the
  cursor row while navigating) is left at herdr's default so the cursor stays visible. Also from the same message:
  "cuando cambio de un space a otro, el borde de color empieza a parpadear": not reproduced. Switching herdr spaces by
  CLI four times, recorded at 60 fps on the screen edge (Ghostty in front; its title carries the space's name and
  changes at each switch): the JankyBorders border held 4 px, the same place and color in all 303 frames, and its
  windows did not change.
- L12 (2026-10-26, user, verbatim): "esta ok la seleccion de space, pero de agents no esta activada creo porque no se pone
  en blanco como el space" and "revisa cual es la mejor opcion de hacerlo y que no gaste muchos recursos y que nunca
  falle". Cause (herdr 0.9.5, src/client/shell/agent_sidebar.rs and src/ui/sidebar.rs): an agent's `focused` is its
  pane's focus flag, and only the `workspace` token takes the focus style (bold text color; the rest of the time
  subtext0); every other token kind, the session title included, is gray whatever the focus. Chosen: the space's name
  leads each agent, the title and model sit below it, all herdr tokens (no helper, no events, nothing to go stale).
  Rejected: a watcher that marks the focused agent in a custom token with a zero-width character and a style rule
  (one more event to follow, and agent names vanish if the watcher is down). A reload gave herdr's 26-column sidebar
  back, which cut the rows: ui.sidebar_min_width = 30 (a sidebar dragged wider keeps its width).
- L13 (2026-10-26, user, verbatim): "mira ahora no aparece el nombre del agente, yo quiero que aparezca el nombre del agente
  y que se pinte en blanco eso te lo dije explicitamente ese cambia y que evaluaras la mejor opcion de hacerlo,
  respetando el cosumo de recursos y que funcione siempre y en tiempo real". The native option (L12) dropped the agent's
  name, so it is reverted: herdr colors by focus only the `workspace` token, so spaces-watch puts each agent's name in
  $aname_dim, or $aname_hot while its pane is the one in front (the focused pane of the active tab of the focused space),
  clearing the other in the same report; the rows style them (hot: bold, #cdd6f4). Focus events (pane/tab/workspace
  .focused) run a light pass: two RPC questions and at most two reports, losing agent first so two names are never
  bright together; no git, no gh. Measured: herdr raises no focus event idle or from a report (three at once per
  switch); the white follows a switch in under 0.6 s with the poll's own delay; idle 0.02 s CPU in 30 s, 20 switches
  0.07 s CPU, 10 MB flat, one process. If the watcher dies the last names stay (launchd restarts it within 10 s and a
  reconnect republishes everything). The 8d100c9 commit had landed on a local branch the user switched to by hand.
- L14: the review of aa09a6b (approved) warned of two edges, both closed: an agent that loses its name now clears both
  name tokens instead of keeping the last, and a failing workspace.list no longer stops the full pass (git, CI, usage):
  without the spaces nobody knows who is in front, so the names are left as they were (tested through nameReports).
