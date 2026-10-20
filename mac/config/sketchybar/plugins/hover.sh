#!/usr/bin/env bash
# Hover feedback: highlights the item under the mouse. $1 = color on enter, $2 = color on exit
# ("none" turns the background off again, which is what plain items want).
on="${1:-0x44cba6f7}"
off="${2:-none}"

case "$SENDER" in
mouse.clicked)
  # Pressed: flash a stronger tint, then fall back to the hover tint.
  sketchybar --set "$NAME" background.drawing=on background.color=0x99cba6f7
  sleep 0.15
  sketchybar --set "$NAME" background.color="$on"
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
