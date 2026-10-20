#!/usr/bin/env bash
# shellcheck disable=SC1091
source "$CONFIG_DIR/icons.sh"

vol="${INFO:-$(osascript -e 'output volume of (get volume settings)')}"
case "$vol" in
0) icon="$VOL_MUTE" ;;
[1-9] | [1-2][0-9]) icon="$VOL_LOW" ;;
[3-6][0-9]) icon="$VOL_MED" ;;
*) icon="$VOL_HIGH" ;;
esac

sketchybar --set "$NAME" icon="$icon" label="${vol}%"
