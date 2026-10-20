#!/usr/bin/env bash
# shellcheck disable=SC1091
# Highlights the focused AeroSpace workspace and dims the empty ones. $1 = workspace id.
source "$CONFIG_DIR/colors.sh"

focused="${FOCUSED_WORKSPACE:-$(aerospace list-workspaces --focused)}"

if [ "$1" = "$focused" ]; then
  sketchybar --set "$NAME" background.drawing=on background.color="$MAUVE" icon.color="$BASE"
else
  count="$(aerospace list-windows --workspace "$1" --count 2>/dev/null || echo 0)"
  if [ "${count:-0}" -gt 0 ]; then color="$TEXT"; else color="$OVERLAY0"; fi
  sketchybar --set "$NAME" background.drawing=off icon.color="$color"
fi
