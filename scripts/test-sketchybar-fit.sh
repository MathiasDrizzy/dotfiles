#!/usr/bin/env bash
# No box of the bar may ever cover another one or sit under the camera housing, whatever the content: the workspaces of
# the Mac and of the external monitor, a long app name, a long place name, a long track. This starts a SketchyBar of its
# own (temporary HOME, a copy of the config, at the bottom of the screen, `aerospace` and `media-control` replaced by
# stubs that read a scenario), feeds it each scenario and measures where every box ended up. The real bar,
# ~/.config/sketchybar, AeroSpace and the user's windows are never touched. Same isolation as test-sketchybar-anchor.sh.
#   scripts/test-sketchybar-fit.sh [CONFIG_DIR]   (default: this repo's mac/config/sketchybar)
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$ROOT/mac/config/sketchybar}"
SETTLE_SECONDS=1.2
START_TRIES=50
EPSILON=0.5

T="$(mktemp -d)"
NAME="fittest$$"
REAL="$(command -v sketchybar)" || {
  echo "test-sketchybar-fit: sketchybar is not installed"
  exit 1
}
mkdir -p "$T/bin" "$T/name"
ln -s "$REAL" "$T/name/$NAME"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$T/name/$NAME" >"$T/bin/sketchybar"
chmod +x "$T/bin/sketchybar"
export HOME="$T/home"
export CONFIG_DIR="$T/config"
export PATH="$T/bin:$PATH"
mkdir -p "$HOME/.cache/sketchybar" "$HOME/.local/bin"
cp -RL "$SRC" "$CONFIG_DIR"

RC="$CONFIG_DIR/sketchybarrc"
sed -i '' '/^sketchybar --update$/,$d' "$RC"
printf 'sketchybar --bar position=bottom\nsketchybar --update\n' >>"$RC"

# AeroSpace: one row per workspace, "id|monitor (AppKit id, 1 = the Mac)|visible|focused|occupied", read from $HOME/rows.
cat >"$T/bin/aerospace" <<'EOF'
#!/bin/bash
rows="$HOME/rows"
case "$*" in
*"monitor-appkit-nsscreen-screens-id"*) awk -F'|' '{print $1"|"$2"|"$3"|"$4}' "$rows" ;;
"list-workspaces --all") cut -d'|' -f1 "$rows" ;;
"list-workspaces --focused") awk -F'|' '$4=="true"{print $1}' "$rows" ;;
"list-windows --all --format %{workspace}") awk -F'|' '$5=="true"{print $1}' "$rows" ;;
"list-windows --focused"*) echo "Google Chrome" ;;
esac
exit 0
EOF
# media-control: the track in $HOME/track as "title|artist", or nothing playing.
cat >"$T/bin/media-control" <<'EOF'
#!/bin/bash
[ -s "$HOME/track" ] || exit 0
IFS='|' read -r title artist <"$HOME/track"
printf '{"bundleIdentifier":"com.spotify.client","playing":true,"title":"%s","artist":"%s"}\n' "$title" "$artist"
EOF
chmod +x "$T/bin/aerospace" "$T/bin/media-control"
printf '#!/bin/sh\nexit 0\n' >"$T/bin/blueutil"
chmod +x "$T/bin/blueutil"

bar_pid=""
cleanup() {
  [ -n "$bar_pid" ] && kill "$bar_pid" 2>/dev/null
  pkill -f "$CONFIG_DIR/plugins/" 2>/dev/null
  wait 2>/dev/null
  rm -rf "$T"
  rm -f "/tmp/${NAME}_$(id -un).lock"
}
trap cleanup EXIT

scene_rows() { # "id:monitor:state" ...  state = f (focused), v (visible, not focused), o (occupied), fo / vo, - (empty)
  : >"$HOME/rows"
  local spec id mon state visible focused occupied
  for spec in "$@"; do
    IFS=: read -r id mon state <<<"$spec"
    visible=false focused=false occupied=false
    case "$state" in f*) visible=true focused=true ;; v*) visible=true ;; esac
    case "$state" in *o) occupied=true ;; esac
    echo "$id|$mon|$visible|$focused|$occupied" >>"$HOME/rows"
  done
}

start_bar() {
  bar_pid="$(
    sketchybar --config "$RC" >>"$T/bar.log" 2>&1 &
    echo $!
  )"
  for _ in $(seq "$START_TRIES"); do
    [ "$(sketchybar --query bar 2>/dev/null | jq -r '.position')" = bottom ] && break
    sleep 0.1
  done
  sleep "$SETTLE_SECONDS"
  if ! kill -0 "$bar_pid" 2>/dev/null; then
    echo "FAIL  start: the test bar is not up ($(tr '\n' ' ' <"$T/bar.log"))"
    echo "test-sketchybar-fit: ABORTED"
    exit 1
  fi
}

# Every box: name, x, width. A box that is not drawn, or has no width, is not on the bar.
BOXES=(apple front_pill spaces ext_spaces weather.moon weather media_pill vorssaint battery date clock control)
boxes() {
  local box
  for box in "${BOXES[@]}"; do
    sketchybar --query "$box" 2>/dev/null | jq -r --arg n "$box" '
      select(.geometry.drawing == "on") | (.bounding_rects | to_entries[0].value) as $r
      | select($r.size[0] > 0 and $r.origin[0] >= 0) | "\($n) \($r.origin[0]) \($r.size[0])"'
  done
}
screen_width() { sketchybar --query displays | jq -r 'map(select(.frame.x == 0 and .frame.y == 0)) | .[0].frame.w'; }

notch_width() { sed -n 's/^NOTCH_WIDTH=\([0-9]*\).*/\1/p' "$CONFIG_DIR/colors.sh"; }

# Prints the faults of the layout on the bar right now, one per line.
faults() {
  local width notch
  width="$(screen_width)"
  notch="$(notch_width)"
  boxes | sort -k2,2n | awk -v w="$width" -v n="$notch" -v e="$EPSILON" '
    { name[NR] = $1; x[NR] = $2; wd[NR] = $3 }
    END {
      nl = (w - n) / 2; nr = nl + n
      for (i = 1; i <= NR; i++) {
        if (x[i] + wd[i] > nl + e && x[i] < nr - e) printf "%s [%.0f..%.0f] is under the camera housing [%.0f..%.0f]\n", name[i], x[i], x[i] + wd[i], nl, nr
        if (i < NR && x[i] + wd[i] > x[i + 1] + e) printf "%s [%.0f..%.0f] covers %s [%.0f..%.0f]\n", name[i], x[i], x[i] + wd[i], name[i + 1], x[i + 1], x[i + 1] + wd[i + 1]
      }
    }'
}

drawn() { sketchybar --query "$1" 2>/dev/null | jq -r '.geometry.drawing'; }

settle() { # the aerospace refresh, the app name, the track and the fit, as the plugins do them
  sketchybar --trigger aerospace_workspace_change >/dev/null
  sleep 0.6
  "$CONFIG_DIR/plugins/app_name.sh" "$1" >/dev/null 2>&1 &
  "$CONFIG_DIR/plugins/media.sh" >/dev/null 2>&1
  sketchybar --set weather label="$2" >/dev/null
  "$CONFIG_DIR/plugins/fit.sh" >/dev/null 2>&1
  sleep "$SETTLE_SECONDS"
}

fails=0
report() { # name, faults
  [ -n "${VERBOSE:-}" ] && echo "        drawn: $(for i in ext_gap ext.mark ext.more space.more $(seq -f 'space.%g' 1 12) $(seq -f 'ext.%g' 1 12); do [ "$(drawn "$i")" = on ] && printf '%s ' "$i"; done)"
  [ -n "${VERBOSE:-}" ] && boxes | sort -k2,2n | awk '{printf "        %-12s %6.0f..%-6.0f\n", $1, $2, $2 + $3}'
  if [ -z "$2" ]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1"
    printf '        %s\n' "$2"
    fails=$((fails + 1))
  fi
}
scene() { # name, app name, place, track, rows...
  local name="$1" app="$2" place="$3" track="$4"
  shift 4
  scene_rows "$@"
  printf '%s' "$track" >"$HOME/track"
  settle "$app" "$place"
  report "$name" "$(faults)"
}

# The rc makes one item per workspace it finds: twelve, so the scenarios can use more than the ten of a real setup.
scene_rows 1:1:f 2:1:- 3:1:- 4:1:- 5:1:- 6:1:- 7:1:- 8:1:- 9:1:- 10:2:v 11:2:- 12:2:-
start_bar
if grep -qiE 'error|invalid|unknown|\[!\]' "$T/bar.log"; then
  echo "FAIL  start: $(tr '\n' ' ' <"$T/bar.log")"
  fails=$((fails + 1))
fi

LONG_TRACK='Lose Yourself to Dance (feat. Pharrell Williams)|Daft Punk and a Very Long Collaboration Name'
LONG_PLACE='Pedro Aguirre Cerda 14°C'
# 1 workspace of the Mac, nothing else: the plain bar.
scene "the plain bar, one workspace" "Ghostty" "La Florida 14°C" "" 1:1:f
# The case from the report: two on the Mac, two on the external monitor, then four on the Mac.
scene "2 on the Mac, 2 on the external monitor" "Google Chrome" "La Florida 14°C" "" 1:1:fo 2:1:o 3:2:vo 4:2:o
scene "4 on the Mac, 2 on the external monitor" "Google Chrome" "La Florida 14°C" "C.R.E.A.M.|Wu-Tang" 1:1:fo 2:1:o 5:1:o 6:1:o 3:2:vo 4:2:o
# Everything at its longest at once.
scene "9 on the Mac, 3 on the external monitor, a long app name, place and track" "Visual Studio Code - Insiders" "$LONG_PLACE" "$LONG_TRACK" \
  1:1:fo 2:1:o 3:1:o 4:1:o 5:1:o 6:1:o 7:1:o 8:1:o 9:1:o 10:2:vo 11:2:o 12:2:o
# The external monitor shows an empty workspace: it must still be on the bar.
scene "an empty workspace on the external monitor" "Ghostty" "La Florida 14°C" "" 1:1:fo 2:1:o 10:2:v
if [ "$(drawn ext.10)" = on ] && [ "$(boxes | grep -c '^ext_spaces ')" -eq 1 ]; then echo "PASS  the visible empty workspace of the external monitor is on the bar"; else
  echo "FAIL  the visible empty workspace of the external monitor is not on the bar"
  fails=$((fails + 1))
fi
# No external monitor: its pill is gone, with its gap.
scene "no external monitor" "Ghostty" "La Florida 14°C" "" 1:1:fo 2:1:o
if [ "$(boxes | grep -c '^ext_spaces ')" -eq 0 ]; then echo "PASS  without an external monitor its pill is not drawn"; else
  echo "FAIL  without an external monitor its pill is still drawn"
  fails=$((fails + 1))
fi

[ "$fails" -eq 0 ] && echo "test-sketchybar-fit: PASS" || echo "test-sketchybar-fit: $fails FAIL"
[ "$fails" -eq 0 ]
