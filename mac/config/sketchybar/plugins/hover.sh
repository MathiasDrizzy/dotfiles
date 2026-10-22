#!/usr/bin/env bash
# Hover feedback: highlights the item under the mouse. $1 = color on enter, $2 = color on exit
# ("none" turns the background off again, which is what plain items want).
on="${1:-0x44cba6f7}"
off="${2:-none}"

case "$SENDER" in
mouse.clicked)
  # Pressed: flash a stronger tint, then release it (the next mouse.entered brings the hover tint back).
  sketchybar --set "$NAME" background.drawing=on background.color=0x99cba6f7
  sleep 0.15
  if [ "$off" = none ]; then
    sketchybar --set "$NAME" background.drawing=off
  else
    sketchybar --set "$NAME" background.color="$off"
  fi
  ;;
mouse.entered) sketchybar --set "$NAME" background.drawing=on background.color="$on" ;;
mouse.exited)
  if [ "$off" = none ]; then
    sketchybar --set "$NAME" background.drawing=off
  else
    sketchybar --set "$NAME" background.color="$off"
  fi
  ;;
esac
