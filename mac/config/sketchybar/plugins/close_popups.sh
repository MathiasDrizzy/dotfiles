#!/usr/bin/env bash
# Closes every popup (Apple menu and active-app menus); run by the other items when they are clicked.
# shellcheck disable=SC1091
source "$CONFIG_DIR/colors.sh"

sketchybar --set apple popup.drawing=off background.color="$BAR_COLOR" icon.color="$TEXT" \
  --set front_app popup.drawing=off --set front_pill background.color="$BAR_COLOR"
