#!/usr/bin/env bash
# The Control Center item must keep its place and its width, so the panel always opens under it. This starts a SketchyBar of
# its own (a temporary HOME and a copy of the config, without the rc's background watchers, at the bottom of the screen so it
# never covers the real bar), runs every action that used to move the item, and samples the item's frame before, during
# and after each one. The real bar, ~/.config/sketchybar and the user's windows are never touched.
# SketchyBar names an instance (its lock file and its mach port) after the name it was run as, not BAR_NAME: the binary is
# linked under another name and a `sketchybar` first in PATH runs it, so the rc, the plugins and this script all talk to the
# test bar. Nothing is sent before the test bar is up and answering as itself.
#   scripts/test-sketchybar-anchor.sh [CONFIG_DIR]   (default: this repo's mac/config/sketchybar)
# Needs a logged-in macOS session with SketchyBar installed; prints one PASS/FAIL line per action.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$ROOT/mac/config/sketchybar}"
ITEM=control
SETTLE_SECONDS=1.5 # long enough for any slide (0.45 s) and the plugins a change triggers
START_TRIES=50
# A reload destroys every item and the bar's windows, then runs the rc again (SketchyBar 2.24.1, event_hotload in
# src/event.c): the item is off the bar until the rc makes it, which it does first. More than this many samples (~10 ms each)
# means something now runs before it.
REBUILD_MAX_ABSENT=10

T="$(mktemp -d)"
NAME="anchortest$$"
REAL="$(command -v sketchybar)" || { echo "test-sketchybar-anchor: sketchybar is not installed"; exit 1; }
mkdir -p "$T/bin" "$T/name"
ln -s "$REAL" "$T/name/$NAME"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$T/name/$NAME" >"$T/bin/sketchybar"
chmod +x "$T/bin/sketchybar"
export HOME="$T/home"
export CONFIG_DIR="$T/config"
export PATH="$T/bin:$PATH"
mkdir -p "$HOME/.cache/sketchybar"
cp -RL "$SRC" "$CONFIG_DIR"

# The watchers the rc starts after its first --update belong to the real bar (some replace the running ones): cut.
RC="$CONFIG_DIR/sketchybarrc"
sed -i '' '/^sketchybar --update$/,$d' "$RC"
printf 'sketchybar --bar position=bottom\nsketchybar --update\n' >>"$RC"

# A Bluetooth device that connects mid-test (its name used to widen the item).
cat >"$T/bin/blueutil" <<'EOF'
#!/bin/sh
case "$1" in
--power) echo 1 ;;
--connected) if [ -e "$HOME/bt" ]; then echo '[{"name":"AirPods Pro de Prueba"}]'; else echo '[]'; fi ;;
esac
EOF
chmod +x "$T/bin/blueutil"

bar_pid=""
cleanup() {
  [ -n "$bar_pid" ] && kill "$bar_pid" 2>/dev/null
  pkill -f "$CONFIG_DIR/plugins/" 2>/dev/null
  wait 2>/dev/null
  rm -rf "$T"
}
trap cleanup EXIT

# Up, alive and answering as the test bar (the only one at the bottom of the screen), or the test stops right here.
start_bar() {
  bar_pid="$(
    sketchybar --config "$RC" >>"$T/bar.log" 2>&1 &
    echo $!
  )" # started from a subshell: not a job of this one, so its kill prints nothing
  for _ in $(seq "$START_TRIES"); do
    [ "$(sketchybar --query bar 2>/dev/null | jq -r '.position')" = bottom ] && break
    sleep 0.1
  done
  sleep "$SETTLE_SECONDS"
  if ! kill -0 "$bar_pid" 2>/dev/null || [ "$(sketchybar --query bar 2>/dev/null | jq -r '.position')" != bottom ]; then
    echo "FAIL  start: the test bar is not up ($(tr '\n' ' ' <"$T/bar.log")); stopped before sending anything"
    echo "test-sketchybar-anchor: ABORTED"
    exit 1
  fi
}

frame() { # "x width" of the item, "hidden", "absent" (the bar has no such item, as while it reloads) or "noreply"
  local query
  query="$(sketchybar --query "$ITEM" 2>"$T/query.err")"
  if grep -q 'not found' "$T/query.err"; then
    echo absent
    return
  fi
  if [ -z "$query" ]; then
    echo "noreply $(tr '\n' ' ' <"$T/query.err")"
    return
  fi
  jq -r <<<"$query" '
    if .geometry.drawing == "on" then (.bounding_rects | to_entries[0].value | "\(.origin[0]) \(.size[0])") else "hidden" end'
}

fails=0
check() { # name, command...: frame before, samples while it runs and settles, frame after
  local name="$1" before after samples
  shift
  before="$(frame)"
  : >"$T/samples"
  (while :; do frame >>"$T/samples"; done) &
  local sampler=$!
  "$@" >/dev/null 2>&1
  sleep "$SETTLE_SECONDS"
  kill "$sampler" 2>/dev/null
  wait "$sampler" 2>/dev/null
  after="$(frame)"
  # A query the busy bar left unanswered is no frame at all: counted, never compared.
  noreply="$(grep -c '^noreply' "$T/samples")"
  samples="$(grep -v '^noreply' "$T/samples" | sort -u | tr '\n' ';')"
  if [ "$before" = "$after" ] && [ "$samples" = "$before;" ] && [ "$before" != hidden ]; then
    echo "PASS  $name: [$before] in $(wc -l <"$T/samples" | tr -d ' ') samples ($noreply unanswered)"
  else
    echo "FAIL  $name: before [$before] after [$after] seen [$samples] counts [$(sort "$T/samples" | uniq -c | awk '{c=$1; $1=""; printf "%s x%s;", $0, c}')] over $(wc -l <"$T/samples" | tr -d ' ') samples"
    fails=$((fails + 1))
  fi
}

toggle_drawer() { NAME=chevron "$CONFIG_DIR/plugins/toggle.sh"; }
twice() { "$@" && "$@"; }
space_change() {
  sketchybar --trigger aerospace_workspace_change FOCUSED_WORKSPACE=2 PREV_WORKSPACE=1
  sleep 0.5
  sketchybar --trigger aerospace_workspace_change FOCUSED_WORKSPACE=1 PREV_WORKSPACE=2
}
front_app() { sketchybar --trigger front_app_switched INFO="Google Chrome"; }
battery_text() { sketchybar --set battery label="100%" && sleep 0.5 && sketchybar --set battery label="5%"; }
clock_text() { sketchybar --set clock label="31-12-2026 · 23:59 extra"; }
wifi_change() { sketchybar --trigger wifi_change; }
volume_change() { sketchybar --trigger volume_change INFO=100; }
bluetooth() { touch "$HOME/bt" && sketchybar --update; }
display_change() { sketchybar --trigger display_change && sketchybar --bar display=main; }
fullscreen() { sketchybar --trigger space_change; }
reload() { sketchybar --reload; }
restart() { # a new session ends every process of the old one, its plugin scripts too (left alive, they set items not yet made)
  kill "$bar_pid" 2>/dev/null
  pkill -f "$CONFIG_DIR/plugins/" 2>/dev/null
  while kill -0 "$bar_pid" 2>/dev/null || pgrep -f "$CONFIG_DIR/plugins/" >/dev/null; do sleep 0.05; done
  start_bar
}

start_bar
if grep -qiE 'error|invalid|unknown|not found' "$T/bar.log"; then
  echo "FAIL  start: $(tr '\n' ' ' <"$T/bar.log")"
  fails=$((fails + 1))
else
  echo "PASS  start: no message from SketchyBar"
fi
if [ "$(frame)" = hidden ]; then
  echo "FAIL  start: the item starts hidden (in the drawer); opened to measure the rest"
  fails=$((fails + 1))
  toggle_drawer >/dev/null 2>&1
  sleep "$SETTLE_SECONDS"
fi
check "the drawer opens and closes" twice toggle_drawer
check "the workspace changes" space_change
check "the app in front changes" front_app
check "the battery text changes" battery_text
check "the clock text changes" clock_text
check "Wi-Fi changes" wifi_change
check "the volume changes" volume_change
check "a Bluetooth device connects" bluetooth
check "the display changes" display_change
check "an app goes full screen" fullscreen
# Off the bar for a moment (rebuilt by SketchyBar itself), and only back at the very same place: never anywhere else.
before_reload="$(frame)"
: >"$T/samples"
(while :; do frame >>"$T/samples"; done) &
sampler=$!
reload
sleep "$SETTLE_SECONDS"
kill "$sampler" 2>/dev/null
wait "$sampler" 2>/dev/null
absent="$(grep -c '^absent$' "$T/samples")"
others="$(grep -v -e '^noreply' -e '^absent$' "$T/samples" | sort -u | grep -vxF "$before_reload" | tr '\n' ';')"
if [ -z "$others" ] && [ "$(frame)" = "$before_reload" ] && [ "$absent" -le "$REBUILD_MAX_ABSENT" ]; then
  echo "PASS  the bar reloads: back at [$before_reload], never elsewhere; off the bar for $absent of $(wc -l <"$T/samples" | tr -d ' ') samples (SketchyBar rebuilds every item)"
else
  echo "FAIL  the bar reloads: before [$before_reload] after [$(frame)] elsewhere [$others] absent $absent samples"
  fails=$((fails + 1))
fi
# A new session has no bar until it starts: the item must come back where it was, and stay put from its first frame.
before_restart="$(frame)"
restart
check "the bar restarts (a new session): steady from its first frame" sleep 0
if [ "$(frame)" = "$before_restart" ] && [ "$before_restart" != hidden ]; then
  echo "PASS  the bar restarts (a new session): back at [$before_restart]"
else
  echo "FAIL  the bar restarts (a new session): before [$before_restart] after [$(frame)]"
  fails=$((fails + 1))
fi
# This script's own queries fail while the bar reloads (already counted as "absent" above); every other message is a fault.
own="Query: Invalid query, or item '$ITEM' not found"
others="$(grep -iE 'error|invalid|unknown|not found|\[!\]' "$T/bar.log" | grep -vF "$own")"
if [ -n "$others" ]; then
  echo "FAIL  log: $(tr '\n' ' ' <<<"$others")"
  fails=$((fails + 1))
else
  echo "PASS  log: no message from SketchyBar ($(grep -cF "$own" "$T/bar.log") from this script's own queries while the item was absent)"
fi

[ "$fails" -eq 0 ] && echo "test-sketchybar-anchor: PASS" || echo "test-sketchybar-anchor: $fails FAIL"
[ "$fails" -eq 0 ]
