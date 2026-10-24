#!/usr/bin/env bash
# No plugin may wait forever on an outside command, and none may pile up: they run on timers and events, so a command
# that hangs (a loaded Mac, a stuck system service) used to be started again by every tick while the first one waited,
# by the dozens, until the Mac crawled. Each case here hangs one outside command and checks the plugin returns within
# its limit, leaves nothing running, and (for the weather) keeps the real place instead of the network's guess.
# Everything is stubbed (sketchybar itself, aerospace, ctlcenter, media-control, pmset, CoreLocationCLI, curl,
# shortcuts) in a temporary HOME: no bar is opened, and the user's apps and settings are never touched.
#   scripts/test-sketchybar-no-pileup.sh [CONFIG_DIR]   (default: this repo's mac/config/sketchybar)
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$ROOT/mac/config/sketchybar}"
T="$(mktemp -d)"
HANG="300$$" # the stubs hang in `sleep $HANG`: a duration no other process has, matched to the end of its command line
export HOME="$T/home"
export CONFIG_DIR="$T/config"
export PATH="$T/bin:$PATH"
CACHE="$HOME/.cache/sketchybar"
mkdir -p "$T/bin" "$CACHE" "$HOME/.local/bin"
cp -RL "$SRC" "$CONFIG_DIR"

cleanup() {
  pkill -f "$CONFIG_DIR/plugins/" 2>/dev/null # only this run's plugins: CONFIG_DIR is inside its own temporary directory
  pkill -f "sleep $HANG\$" 2>/dev/null
  rm -rf "$T"
}
trap cleanup EXIT

stub() { # name, body
  printf '#!/bin/bash\n%s\n' "$2" >"$T/bin/$1"
  chmod +x "$T/bin/$1"
}
# SketchyBar: every call is logged; a query answers as an item that is drawn.
stub sketchybar "echo \"\$*\" >>\"$T/sketchybar.log\"
case \"\$1\" in --query) echo '{\"geometry\":{\"drawing\":\"on\"},\"label\":{\"value\":\"\"},\"bounding_rects\":{}}' ;; esac
exit 0"
stub media-control "exec sleep $HANG"
stub aerospace "exec sleep $HANG"
stub pmset "exec sleep $HANG"
stub CoreLocationCLI "exec sleep $HANG"
stub shortcuts "exit 1"
# curl: the network's place is the provider's commune (Conchalí); Open-Meteo answers 15 degrees.
stub curl "case \"\$*\" in
*wttr.in*) echo '{\"nearest_area\":[{\"latitude\":\"-33.44\",\"longitude\":\"-70.65\"}]}' ;;
*nominatim*) echo '{\"address\":{\"city\":\"Conchalí\"}}' ;;
*open-meteo*) echo '{\"current\":{\"temperature_2m\":15.2}}' ;;
esac"
cp "$T/bin/aerospace" "$HOME/.local/bin/ctlcenter" # a ctlcenter that never answers

fails=0
check() { # name, expected, actual
  if [ "$2" = "$3" ]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 (expected '$2', got '$3')"
    fails=$((fails + 1))
  fi
}
hung() { pgrep -f "sleep $HANG\$" | wc -l | tr -d ' '; }
within() { # seconds, command...: 1 when it returned in time
  local limit="$1" start
  shift
  start=$(date +%s)
  # The test has its own limit too: a plugin with none (the bug) would hang it forever instead of failing it.
  /usr/bin/perl -e 'alarm shift; exec @ARGV' $((limit + 5)) "$@" >/dev/null 2>&1
  [ $(($(date +%s) - start)) -le "$limit" ] && echo 1 || echo "took $(($(date +%s) - start)) s"
}

# media.sh: six runs at once while media-control hangs (the poll and the events of a busy minute).
for _ in 1 2 3 4 5 6; do
  MEDIA_CONTROL_SECONDS=2 NAME=media /usr/bin/perl -e 'alarm shift; exec @ARGV' 10 "$CONFIG_DIR/plugins/media.sh" >/dev/null 2>&1 &
done
sleep 1
check "media.sh: a hung media-control is asked once, not once per run" 1 "$(hung)"
wait
# The run a note brings back asks once more, also bounded: wait for it with a deadline instead of a fixed pause.
settle() { # seconds: until no hung command and no media lock are left, or the deadline
  local _
  for _ in $(seq $(($1 * 10))); do
    [ "$(hung)" = 0 ] && [ ! -e "$CACHE/media_busy" ] && return
    sleep 0.1
  done
}
settle 10
check "media.sh: the hung media-control is ended by its limit" 0 "$(hung)"
check "media.sh: its lock is released" 0 "$([ -e "$CACHE/media_busy" ] && echo 1 || echo 0)"

# aerospace.sh: AeroSpace never answers; the refresh still returns, and lets go of its lock.
check "aerospace.sh: a hung aerospace does not hold the refresh" 1 \
  "$(SENDER=aerospace_workspace_change NAME=space.1 within 25 "$CONFIG_DIR/plugins/aerospace.sh" 1 refresh)"
check "aerospace.sh: no hung aerospace is left" 0 "$(hung)"
check "aerospace.sh: its lock is released" 0 "$([ -e "$CACHE/spaces_busy" ] && echo 1 || echo 0)"

# cover.sh: ctlcenter never answers whether something needs the cover.
check "cover.sh: a hung ctlcenter does not hold the cover" 1 "$(BACKDROP_SECONDS=1 within 15 "$CONFIG_DIR/plugins/cover.sh" off)"
check "cover.sh: no hung ctlcenter is left" 0 "$(hung)"

# battery.sh: pmset never answers.
check "battery.sh: a hung pmset does not hold it" 1 "$(NAME=battery within 6 "$CONFIG_DIR/plugins/battery.sh")"
check "battery.sh: no hung pmset is left" 0 "$(hung)"

# control.sh: networksetup and ipconfig never answer.
stub networksetup "exec sleep $HANG"
stub ipconfig "exec sleep $HANG"
check "control.sh: hung network commands do not hold it" 1 "$(NAME=control within 8 "$CONFIG_DIR/plugins/control.sh")"
check "control.sh: no hung network command is left" 0 "$(hung)"

# about.sh: System Events never answers the click.
stub osascript "exec sleep $HANG"
check "about.sh: a hung osascript does not hold it" 1 "$(within 7 "$CONFIG_DIR/plugins/about.sh")"
check "about.sh: no hung osascript is left" 0 "$(hung)"

# weather.sh: Location Services is slow (the Mac is loaded); the last place it gave is kept, not the network's commune.
printf '%s\t%s\t%s\n' -33.437 -70.650 Providencia >"$CACHE/weather_place"
: >"$T/sketchybar.log"
NAME=weather LOCATE_SECONDS=1 /usr/bin/perl -e 'alarm shift; exec @ARGV' 30 "$CONFIG_DIR/plugins/weather.sh" >/dev/null 2>&1
check "weather.sh: a slow fix keeps the last real place" 1 \
  "$(grep -c 'label=Providencia 15°C' "$T/sketchybar.log" | tr -d ' ')"
check "weather.sh: no hung CoreLocationCLI is left" 0 "$(hung)"

# weather.sh: a fix whose commune macOS could not name still gives the exact point, named by OpenStreetMap.
rm -f "$CACHE/weather_place"
stub CoreLocationCLI "printf '%s\\t%s\\t\\n' -33.437 -70.650"
: >"$T/sketchybar.log"
NAME=weather /usr/bin/perl -e 'alarm shift; exec @ARGV' 30 "$CONFIG_DIR/plugins/weather.sh" >/dev/null 2>&1
check "weather.sh: a fix without a commune is still used" 1 "$(grep -c 'label=Conchalí 15°C' "$T/sketchybar.log" | tr -d ' ')"
check "weather.sh: ...and is not remembered as a place" 0 "$([ -e "$CACHE/weather_place" ] && echo 1 || echo 0)"
check "weather.sh: ...and leaves nothing running" 0 "$(hung)"

if [ "$fails" -eq 0 ]; then echo "test-sketchybar-no-pileup: PASS"; else
  echo "test-sketchybar-no-pileup: $fails FAILED"
  exit 1
fi
