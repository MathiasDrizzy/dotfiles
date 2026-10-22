#!/usr/bin/env bash
# Apple menu: toggles its popup on click, highlights while the mouse is over it or the popup is open, and closes the
# popup as soon as the mouse leaves the item and the popup. "apple.sh close" is run by the popup entries.
# shellcheck disable=SC1091
source "$CONFIG_DIR/colors.sh"

hover="$APPLE_HOVER"
open_color="$APPLE_PRESSED"

close() { sketchybar --set apple popup.drawing=off background.color="$APPLE_BG" icon.color="$APPLE_ICON"; }

[ "${1:-}" = close ] && {
  close
  exit 0
}

is_open="$(sketchybar --query apple | jq -r '.popup.drawing')"
case "$SENDER" in
mouse.clicked)
  if [ "$is_open" = on ]; then
    close
  else
    sketchybar --set front_pill popup.drawing=off background.color="$BAR_COLOR" --set apple popup.drawing=on background.color="$open_color" icon.color="$APPLE_ICON"
  fi
  ;;
mouse.entered) [ "$is_open" = on ] || sketchybar --set apple background.color="$hover" ;;
mouse.exited) [ "$is_open" = on ] || sketchybar --set apple background.color="$APPLE_BG" ;;
mouse.exited.global) close ;;
esac
