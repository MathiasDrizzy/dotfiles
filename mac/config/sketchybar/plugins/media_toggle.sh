#!/usr/bin/env bash
# Play/pause button: flips the icon at once (the player takes a moment to answer), then toggles the player
# and lets media.sh confirm the real state.
# shellcheck disable=SC1091
source "$CONFIG_DIR/icons.sh"

if [ "$(sketchybar --query media_play | jq -r '.icon.value')" = "$PAUSE" ]; then
  sketchybar --set media_play icon="$PLAY"
else
  sketchybar --set media_play icon="$PAUSE"
fi
"$CONFIG_DIR/plugins/close_popups.sh" &
media-control toggle-play-pause
"$CONFIG_DIR/plugins/media.sh"
