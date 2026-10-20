#!/usr/bin/env bash
# Memory in use right now: app memory + wired + compressed, like Activity Monitor's "Memory Used".
# shellcheck disable=SC1091
case "$SENDER" in mouse.*) exec "$CONFIG_DIR/plugins/hover.sh" ;; esac
source "$CONFIG_DIR/colors.sh"

pct="$(vm_stat | awk -v total="$(sysctl -n hw.memsize)" '
  /page size of/ {ps = $8}
  /Anonymous pages/ {anon = $3}
  /Pages wired down/ {wired = $4}
  /occupied by compressor/ {comp = $5}
  END {printf "%d", (anon + wired + comp) * ps * 100 / total}')"
[ -z "$pct" ] && exit 0

color="$TEXT"
[ "$pct" -ge 85 ] && color="$RED"
sketchybar --set "$NAME" label="RAM ${pct}%" label.color="$color"
