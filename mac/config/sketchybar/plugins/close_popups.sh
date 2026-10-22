#!/usr/bin/env bash
# Closes every popup (Apple menu and active-app menus); run by the other items when they are clicked.
# shellcheck disable=SC1091
source "$CONFIG_DIR/colors.sh"

sketchybar --set apple popup.drawing=off background.color="$APPLE_BG" icon.color="$APPLE_ICON" \
  --set front_pill popup.drawing=off background.color="$BAR_COLOR"
