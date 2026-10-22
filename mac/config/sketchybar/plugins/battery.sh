#!/usr/bin/env bash
# neutonfoo/dotfiles's battery: five levels, each with its own Macchiato color, and a bolt while on power.
# shellcheck disable=SC1091
source "$CONFIG_DIR/colors.sh"
case "$SENDER" in mouse.*) exec "$CONFIG_DIR/plugins/hover.sh" "$BAR_HOVER" "$BAR_COLOR" ;; esac
source "$CONFIG_DIR/icons.sh"

batt="$(pmset -g batt)"
pct="$(grep -Eo '[0-9]+%' <<<"$batt" | head -1 | tr -d '%')"
[ -z "$pct" ] && exit 0

if [ "$pct" -ge 80 ]; then
  icon="$BAT_FULL" color="$GREEN"
elif [ "$pct" -ge 70 ]; then
  icon="$BAT_THREE_QUARTERS" color="$YELLOW"
elif [ "$pct" -ge 40 ]; then
  icon="$BAT_HALF" color="$PEACH"
elif [ "$pct" -ge 10 ]; then
  icon="$BAT_QUARTER" color="$MAROON"
else
  icon="$BAT_EMPTY" color="$RED"
fi
if grep -q 'AC Power' <<<"$batt"; then
  icon="$BAT_CHARGING" color="$YELLOW"
fi

sketchybar --set "$NAME" icon="$icon" icon.color="$color" label="${pct}%"
