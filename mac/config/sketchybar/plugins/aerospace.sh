#!/usr/bin/env bash
# Shows only the focused and the occupied AeroSpace workspaces, highlights the focused one and tints the one under the mouse. $1 = workspace id.
# shellcheck disable=SC1091
source "$CONFIG_DIR/colors.sh"

focused="${FOCUSED_WORKSPACE:-$(aerospace list-workspaces --focused)}"

if [ "$1" = "$focused" ]; then
  sketchybar --set "$NAME" background.drawing=on drawing=on background.color="$MAUVE" icon.color="$BASE"
  exit 0
fi

count="$(aerospace list-windows --workspace "$1" --count 2>/dev/null || echo 0)"
if [ "${count:-0}" -eq 0 ]; then
  sketchybar --set "$NAME" drawing=off
  exit 0
fi

if [ "$SENDER" = mouse.entered ]; then
  sketchybar --set "$NAME" background.drawing=on drawing=on background.color=0x44cba6f7 icon.color="$TEXT"
else
  sketchybar --set "$NAME" drawing=on background.drawing=off icon.color="$TEXT"
fi
