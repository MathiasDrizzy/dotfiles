#!/usr/bin/env bash
# shellcheck disable=SC1091
# Shows the current track (dimmed with a pause icon while paused) and hides the item when there is no track.
source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/icons.sh"

info="$(media-control get 2>/dev/null)"
playing="$(jq -r '.playing // false' <<<"$info" 2>/dev/null)"
title="$(jq -r '.title // empty' <<<"$info" 2>/dev/null)"
artist="$(jq -r '.artist // empty' <<<"$info" 2>/dev/null)"

if [ -z "$title" ]; then
  sketchybar --set "$NAME" drawing=off
  exit 0
fi

label="$title"
[ -n "$artist" ] && label="$title - $artist"
if [ "$playing" = "true" ]; then
  sketchybar --set "$NAME" drawing=on icon="$MUSIC" icon.color="$MAUVE" label="$label" label.color="$TEXT"
else
  sketchybar --set "$NAME" drawing=on icon="$PAUSE" icon.color="$OVERLAY0" label="$label" label.color="$OVERLAY0"
fi
