#!/usr/bin/env bash
# Apple menu: toggles its popup on click, highlights while the mouse is over it or the popup is open, and closes the
# popup as soon as the mouse leaves the item and the popup. "apple.sh close" is run by the popup entries.
# shellcheck disable=SC1091
source "$CONFIG_DIR/colors.sh"

hover=0xf0313244
open_color=0xf045475a

close() { sketchybar --set apple popup.drawing=off background.color="$BAR_COLOR" icon.color="$TEXT"; }

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
    sketchybar --set front_app popup.drawing=off background.color="$BAR_COLOR" --set apple popup.drawing=on background.color="$open_color" icon.color="$MAUVE"
  fi
  ;;
mouse.entered) [ "$is_open" = on ] || sketchybar --set apple background.color="$hover" ;;
mouse.exited) [ "$is_open" = on ] || sketchybar --set apple background.color="$BAR_COLOR" ;;
mouse.exited.global) close ;;
esac
