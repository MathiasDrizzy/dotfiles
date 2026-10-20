#!/usr/bin/env bash
# shellcheck disable=SC1091
# Now playing. Shows "Title - Artist" in a fixed 18-character window that bounces back and forth when the text is
# longer (one character per second, pausing at both ends); dimmed with a pause icon while paused. The three media
# items are hidden when no track is loaded. Mouse events go to hover.sh.
export LC_ALL=en_US.UTF-8
case "$SENDER" in mouse.*)
  exec "$CONFIG_DIR/plugins/hover.sh"
  ;;
esac
source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/icons.sh"

WIDTH=18
HOLD=2

info="$(media-control get 2>/dev/null)"
playing="$(jq -r '.playing // false' <<<"$info" 2>/dev/null)"
title="$(jq -r '.title // empty' <<<"$info" 2>/dev/null)"
artist="$(jq -r '.artist // empty' <<<"$info" 2>/dev/null)"

if [ -z "$title" ]; then
  sketchybar --set media drawing=off --set media_prev drawing=off --set media_next drawing=off
  exit 0
fi

text="$title"
[ -n "$artist" ] && text="$title - $artist"

len=${#text}
if [ "$len" -le "$WIDTH" ]; then
  shown="$(printf '%-*s' "$WIDTH" "$text")"
else
  span=$((len - WIDTH))
  t=$(($(date +%s) % (2 * (span + HOLD))))
  if [ "$t" -lt "$HOLD" ]; then
    offset=0
  elif [ "$t" -lt $((HOLD + span)) ]; then
    offset=$((t - HOLD))
  elif [ "$t" -lt $((2 * HOLD + span)) ]; then
    offset=$span
  else
    offset=$((span - (t - 2 * HOLD - span)))
  fi
  shown="${text:offset:WIDTH}"
fi

if [ "$playing" = "true" ]; then
  icon="$MUSIC"
  icon_color="$MAUVE"
  label_color="$TEXT"
else
  icon="$PAUSE"
  icon_color="$OVERLAY0"
  label_color="$OVERLAY0"
fi
sketchybar --set media drawing=on icon="$icon" icon.color="$icon_color" label="$shown" label.color="$label_color" \
  --set media_prev drawing=on --set media_next drawing=on
