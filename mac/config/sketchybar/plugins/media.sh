#!/usr/bin/env bash
# shellcheck disable=SC1091
# Shows the track while something is playing and hides the item otherwise.
source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/icons.sh"

info="$(media-control get 2>/dev/null)"
playing="$(jq -r '.playing // false' <<<"$info" 2>/dev/null)"
title="$(jq -r '.title // empty' <<<"$info" 2>/dev/null)"
artist="$(jq -r '.artist // empty' <<<"$info" 2>/dev/null)"

if [ "$playing" != "true" ] || [ -z "$title" ]; then
  sketchybar --set "$NAME" drawing=off
  exit 0
fi

label="$title"
[ -n "$artist" ] && label="$title - $artist"
sketchybar --set "$NAME" drawing=on icon="$MUSIC" label="$label"
