#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2153
# Now playing, polled every 2 s: updates the buttons and the title and hides everything when no track is loaded. The
# title itself is animated by marquee.sh, which this script starts when needed. The play/pause button shows the action
# the click will do.
source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/icons.sh"

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/sketchybar"
mkdir -p "$CACHE"

info="$(media-control get 2>/dev/null)"
playing="$(jq -r '.playing // false' <<<"$info" 2>/dev/null)"
title="$(jq -r '.title // empty' <<<"$info" 2>/dev/null)"
artist="$(jq -r '.artist // empty' <<<"$info" 2>/dev/null)"

if [ -z "$title" ]; then
  : >"$CACHE/media-text"
  sketchybar --set media drawing=off --set media_prev drawing=off --set media_play drawing=off \
    --set media_next drawing=off
  exit 0
fi

text="$title"
[ -n "$artist" ] && text="$title - $artist"
printf '%s' "$text" >"$CACHE/media-text"
if [ "$(sketchybar --query media | jq -r '.label.value')" != "$text" ]; then
  sketchybar --set media label="$text" label.padding_left=0 label.padding_right=10
fi

if [ "$playing" = "true" ]; then
  play_icon="$PAUSE"
  label_color="$TEXT"
else
  play_icon="$PLAY"
  label_color="$OVERLAY0"
fi
sketchybar --set media drawing=on label.color="$label_color" \
  --set media_play drawing=on icon="$play_icon" --set media_prev drawing=on --set media_next drawing=on

pidfile="$CACHE/marquee.pid"
if ! { [ -s "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; }; then
  nohup "$CONFIG_DIR/plugins/marquee.sh" >/dev/null 2>&1 &
  echo $! >"$pidfile"
fi
