#!/usr/bin/env bash
# CPU and memory in use right now, two items in one pill: sys (CPU) and sys_mem (RAM). CPU comes from top, which samples the interval
# (ps reports a decayed average); memory is app + wired + compressed, like Activity Monitor's "Memory Used".
# shellcheck disable=SC1091
source "$CONFIG_DIR/colors.sh"

[ "$(cat "$PANEL_STATE" 2>/dev/null)" = on ] || exit 0 # hidden: nothing to paint, and top is not free

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
panel_set --set sys label="${cpu}%" label.color="$color" --set sys_mem label="${mem}%" label.color="$color"
