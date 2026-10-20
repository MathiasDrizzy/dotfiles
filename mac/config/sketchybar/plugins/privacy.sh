#!/usr/bin/env bash
# Microphone icon inside the chevron pill: it grows in while macOS shows its recording dot and shrinks away when the dot goes.
# shellcheck disable=SC1091
ICON_WIDTH=18
ANIMATION_CURVE=tanh
ANIMATION_FRAMES=6

if "$HOME/.local/bin/ctlcenter" indicator 2>/dev/null; then width="$ICON_WIDTH"; else width=0; fi
current="$(sketchybar --query "$NAME" | jq -r '.icon.width // 0')"
[ "${current%.*}" = "$width" ] && exit 0
sketchybar --animate "$ANIMATION_CURVE" "$ANIMATION_FRAMES" --set "$NAME" icon.width="$width"
