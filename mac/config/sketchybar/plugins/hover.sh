#!/usr/bin/env bash
# Hover feedback: highlights the item under the mouse. $1 = color on enter, $2 = color on exit
# ("none" turns the background off again, which is what plain items want).
on="${1:-0x44cba6f7}"
off="${2:-none}"

case "$SENDER" in
mouse.entered) sketchybar --set "$NAME" background.drawing=on background.color="$on" ;;
mouse.exited)
  if [ "$off" = none ]; then
    sketchybar --set "$NAME" background.drawing=off
  else
    sketchybar --set "$NAME" background.color="$off"
  fi
  ;;
esac
