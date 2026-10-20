#!/usr/bin/env bash
# Privacy slot at the right end of the bar: macOS draws its recording dot there, so the icon lights up while the dot is on.
# shellcheck disable=SC1091
source "$CONFIG_DIR/colors.sh"

if "$HOME/.local/bin/ctlcenter" indicator 2>/dev/null; then
  sketchybar --set "$NAME" icon.color="$MAUVE"
else
  sketchybar --set "$NAME" icon.color="$OVERLAY0"
fi
