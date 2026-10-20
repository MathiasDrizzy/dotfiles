#!/usr/bin/env bash
# shellcheck disable=SC1091
case "$SENDER" in mouse.*) exec "$CONFIG_DIR/plugins/hover.sh" ;; esac
source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/icons.sh"

batt="$(pmset -g batt)"
pct="$(grep -Eo '[0-9]+%' <<<"$batt" | head -1 | tr -d '%')"
[ -z "$pct" ] && exit 0

if grep -q 'AC Power' <<<"$batt"; then
  icon="$BAT_CHARGING"
  color="$GREEN"
else
  color="$TEXT"
  step=$(((pct + 5) / 10 * 10))
  [ "$step" -gt 100 ] && step=100
  var="BAT_$step"
  icon="${!var}"
  [ "$pct" -le 20 ] && color="$RED"
fi

sketchybar --set "$NAME" icon="$icon" icon.color="$color" label="${pct}%"
