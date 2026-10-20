#!/usr/bin/env bash
# CPU in use right now (top samples the interval, unlike ps, whose %cpu is a decayed average).
# shellcheck disable=SC1091
case "$SENDER" in mouse.*) exec "$CONFIG_DIR/plugins/hover.sh" ;; esac
source "$CONFIG_DIR/colors.sh"

idle="$(top -l 2 -n 0 -s 1 | awk '/CPU usage/ {v=$7} END {gsub("%", "", v); print v}')"
[ -z "$idle" ] && exit 0
load="$(awk -v i="$idle" 'BEGIN {printf "%d", 100 - i}')"

color="$TEXT"
[ "$load" -ge 80 ] && color="$RED"
sketchybar --set "$NAME" label="CPU ${load}%" label.color="$color"
