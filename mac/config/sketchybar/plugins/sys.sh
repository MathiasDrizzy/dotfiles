#!/usr/bin/env bash
# CPU and memory in use right now, one item: "CPU 12%  RAM 64%". CPU comes from top, which samples the interval
# (ps reports a decayed average); memory is app + wired + compressed, like Activity Monitor's "Memory Used".
# shellcheck disable=SC1091
case "$SENDER" in mouse.*) exec "$CONFIG_DIR/plugins/hover.sh" 0xf0313244 0xd91e1e2e ;; esac
source "$CONFIG_DIR/colors.sh"

idle="$(top -l 2 -n 0 -s 1 | awk '/CPU usage/ {v=$7} END {gsub("%", "", v); print v}')"
[ -z "$idle" ] && exit 0
cpu="$(awk -v i="$idle" 'BEGIN {printf "%d", 100 - i}')"

mem="$(vm_stat | awk -v total="$(sysctl -n hw.memsize)" '
  /page size of/ {ps = $8}
  /Anonymous pages/ {anon = $3}
  /Pages wired down/ {wired = $4}
  /occupied by compressor/ {comp = $5}
  END {printf "%d", (anon + wired + comp) * ps * 100 / total}')"
[ -z "$mem" ] && exit 0

color="$TEXT"
{ [ "$cpu" -ge 80 ] || [ "$mem" -ge 85 ]; } && color="$RED"
sketchybar --set "$NAME" label="CPU ${cpu}%  RAM ${mem}%" label.color="$color"
