#!/usr/bin/env bash
# The workspace pills must follow AeroSpace however fast the focus changes: one pill focused (never two, never none), the
# last focus is the one that stays, a late event cannot repaint a focus that is already gone, and the lock that serializes
# the refreshes neither loses an event nor outlives a killed run. Also: a hung `ctlcenter backdrop` must not pile up.
# Same isolation as test-sketchybar-fit.sh: a SketchyBar of its own (temporary HOME, a copy of the config, at the bottom of
# the screen) and `aerospace` and `ctlcenter` replaced by stubs; the real bar, AeroSpace and the user's windows are never
# touched.
#   scripts/test-sketchybar-workspaces.sh [CONFIG_DIR]   (default: this repo's mac/config/sketchybar)
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$ROOT/mac/config/sketchybar}"
START_TRIES=50
SETTLE_SECONDS=1.8 # a refresh and the rerun a note brings
MAUVE=0xffc6a0f6

T="$(mktemp -d)"
NAME="wstest$$"
REAL="$(command -v sketchybar)" || {
  echo "test-sketchybar-workspaces: sketchybar is not installed"
  exit 1
}
mkdir -p "$T/bin" "$T/name"
ln -s "$REAL" "$T/name/$NAME"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$T/name/$NAME" >"$T/bin/sketchybar"
chmod +x "$T/bin/sketchybar"
export HOME="$T/home"
export CONFIG_DIR="$T/config"
export PATH="$T/bin:$PATH"
CACHE="$HOME/.cache/sketchybar"
mkdir -p "$CACHE" "$HOME/.local/bin"
cp -RL "$SRC" "$CONFIG_DIR"
RC="$CONFIG_DIR/sketchybarrc"
sed -i '' '/^sketchybar --update$/,$d' "$RC"
printf 'sketchybar --bar position=bottom\nsketchybar --update\n' >>"$RC"

# AeroSpace: one row per workspace, "id|monitor|visible|focused|occupied", read from $HOME/rows. A file named slow makes the
# answers about the windows take that many seconds (a refresh that is busy while the next event arrives).
cat >"$T/bin/aerospace" <<'EOF2'
#!/bin/bash
rows="$HOME/rows"
[ ! -s "$HOME/slow" ] || [ "${1:-}" != list-windows ] || sleep "$(cat "$HOME/slow")"
case "$*" in
*"monitor-appkit-nsscreen-screens-id"*) awk -F'|' '{print $1"|"$2"|"$3"|"$4}' "$rows" ;;
"list-workspaces --all") cut -d'|' -f1 "$rows" ;;
"list-workspaces --focused") awk -F'|' '$4=="true"{print $1}' "$rows" ;;
"list-workspaces --monitor all --visible") awk -F'|' '$3=="true"{print $1}' "$rows" ;;
"list-windows --all --format %{workspace}") awk -F'|' '$5=="true"{print $1}' "$rows" ;;
"list-windows --focused"*) echo "Ghostty" ;;
esac
exit 0
EOF2
chmod +x "$T/bin/aerospace"
printf '#!/bin/sh\nexit 0\n' >"$T/bin/blueutil"
printf '#!/bin/sh\nexit 0\n' >"$T/bin/media-control"
chmod +x "$T/bin/blueutil" "$T/bin/media-control"

cleanup() {
  pkill -f "$T/name/$NAME" 2>/dev/null # the test bar: its own binary name, in this run's own directory
  # Only the plugins this run's bar started (CONFIG_DIR is inside its own temporary directory): the stubs in $T/bin run and
  # return, so nothing else of this run lives on, and nothing outside it can match.
  pkill -f "$CONFIG_DIR/plugins/" 2>/dev/null
  wait 2>/dev/null
  rm -rf "$T"
  rm -f "/tmp/${NAME}_$(id -un).lock"
}
trap cleanup EXIT

focus_rows() { # focused workspace; all three are occupied
  local id
  : >"$HOME/rows"
  for id in 1 2 3; do
    if [ "$id" = "$1" ]; then echo "$id|1|true|true|true" >>"$HOME/rows"; else echo "$id|1|false|false|true" >>"$HOME/rows"; fi
  done
}
event() { sketchybar --trigger aerospace_workspace_change FOCUSED_WORKSPACE="${1:-}" >/dev/null; }
lit() { # the workspaces whose pill is drawn as the focused one
  local n
  for n in 1 2 3; do
    [ "$(sketchybar --query "space.$n" 2>/dev/null | jq -r '.geometry.background.color')" = "$MAUVE" ] && printf '%s' "$n"
  done
  true
}

fails=0
check() { # name, expected, actual
  if [ "$2" = "$3" ]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 (expected '$2', got '$3')"
    fails=$((fails + 1))
  fi
}
residue() {
  local f
  for f in spaces_busy spaces_again; do [ ! -e "$CACHE/$f" ] || printf '%s ' "$f"; done
}

focus_rows 1
sketchybar --version >/dev/null 2>&1 || true
(sketchybar --config "$RC" >>"$T/bar.log" 2>&1 &)
for _ in $(seq "$START_TRIES"); do
  [ "$(sketchybar --query bar 2>/dev/null | jq -r '.position')" = bottom ] && break
  sleep 0.1
done
sleep "$SETTLE_SECONDS"
if [ -z "$(sketchybar --query bar 2>/dev/null)" ]; then
  echo "FAIL  start: the test bar is not up ($(tr '\n' ' ' <"$T/bar.log"))"
  echo "test-sketchybar-workspaces: ABORTED"
  exit 1
fi
check "the bar starts with the focused workspace lit" 1 "$(lit)"
# The driver item also ticks every second: stop that, so a refresh in flight is always one the test started.
sketchybar --set space.1 update_freq=0 >/dev/null
sleep "$SETTLE_SECONDS"

focus_rows 2
event 2
sleep "$SETTLE_SECONDS"
check "a switch lights exactly the focused pill" 2 "$(lit)"

# A late event: AeroSpace is already on 3, the event still says 1.
focus_rows 3
SENDER=aerospace_workspace_change FOCUSED_WORKSPACE=1 NAME=space.1 "$CONFIG_DIR/plugins/aerospace.sh" 1 refresh
check "a late event carrying an old focus does not repaint it" 3 "$(lit)"

# A burst: thirty events with no pause, the focus moving each time.
for i in $(seq 30); do
  focus_rows $((i % 3 + 1))
  event $((i % 3 + 1)) &
done
wait
sleep $((${SETTLE_SECONDS%.*} + 2))
check "after a burst only the last focus is lit" "$(awk -F'|' '$4=="true"{print $1}' "$HOME/rows")" "$(lit)"
check "a burst leaves no lock or note behind" "" "$(residue)"

# The lock: a refresh that finds it held leaves a note and returns at once.
mkdir "$CACHE/spaces_busy"
start=$(date +%s)
"$CONFIG_DIR/plugins/aerospace.sh" 1 refresh
elapsed=$(($(date +%s) - start))
check "a refresh that finds the lock held returns at once" 1 "$([ "$elapsed" -le 1 ] && echo 1 || echo "$elapsed s")"
check "...and leaves a note for the holder" 1 "$([ -e "$CACHE/spaces_again" ] && echo 1 || echo 0)"
rmdir "$CACHE/spaces_busy"
rm -f "$CACHE/spaces_again"

# A lock left by a killed run is cleared once it is old.
mkdir "$CACHE/spaces_busy"
touch -t "$(date -v-2M +%Y%m%d%H%M.%S)" "$CACHE/spaces_busy"
focus_rows 2
event 2
sleep "$SETTLE_SECONDS"
check "a lock left by a killed run does not freeze the bar" 2 "$(lit)"

# No event is lost: the focus changes while a slow refresh is still running.
echo 1.2 >"$HOME/slow"
focus_rows 1
event 1
sleep 0.4
focus_rows 3
event 3
sleep $((${SETTLE_SECONDS%.*} + 3))
rm -f "$HOME/slow"
check "an event that arrives during a refresh is drawn when it ends" 3 "$(lit)"
sleep 3 # runs that started while it was slow are still finishing
check "...and leaves no lock or note behind" "" "$(residue)"

# Reloads that overlap (hotload on a checkout that touches several files): every workspace bracket keeps all its items.
for _ in 1 2 3; do
  sketchybar --reload >/dev/null 2>&1
  sleep 0.2
done
sleep 6
members() { sketchybar --query "$1" 2>/dev/null | jq '.bracket | length'; }
items_like() { sketchybar --query bar | jq -r '.items[]' | grep -cE "^$1$"; }
check "overlapping reloads leave the workspace bracket whole" "$(items_like 'space\..*')" "$(members spaces)"
check "...and the other monitor's bracket whole" "$(items_like 'ext\..*')" "$(members ext_spaces)"
check "...and no build left running" 0 "$(pgrep -lf "$CONFIG_DIR/sketchybarrc" | grep -vc -- '--config')" # the bar itself names its rc too

# cover.sh remember: ctlcenter backdrop hung for days at 10% of a core. It gets a time limit and is gone after it.
SLEEPER="300$$" # a duration no other process has (the fixed prefix and this PID), matched to the end of the command line
cat >"$HOME/.local/bin/ctlcenter" <<EOF2
#!/bin/bash
[ "\$1" = backdrop ] && exec sleep $SLEEPER
exit 1
EOF2
chmod +x "$HOME/.local/bin/ctlcenter"
start=$(date +%s)
BACKDROP_SECONDS=1 "$CONFIG_DIR/plugins/cover.sh" remember >/dev/null 2>&1
elapsed=$(($(date +%s) - start))
check "a hung ctlcenter backdrop is stopped by its time limit" 1 "$([ "$elapsed" -le 5 ] && echo 1 || echo "$elapsed s")"
check "...and no sleeper is left running" 0 "$(pgrep -f "sleep $SLEEPER\$" | wc -l | tr -d ' ')"

if grep -qiE 'error|invalid|unknown' "$T/bar.log"; then
  echo "FAIL  the bar logged: $(tr '\n' ' ' <"$T/bar.log")"
  fails=$((fails + 1))
fi
if [ "$fails" -eq 0 ]; then echo "test-sketchybar-workspaces: PASS"; else
  echo "test-sketchybar-workspaces: $fails FAILED"
  exit 1
fi
