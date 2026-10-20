#!/usr/bin/env bash
# Smooth title marquee for the media item: shows a fixed 20-character window over "Title - Artist" and bounces it
# back and forth (about 3 characters per second, pausing at both ends). Started by media.sh; it exits on its own
# when there is no track or SketchyBar is gone.
export LC_ALL=en_US.UTF-8
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/sketchybar"
WIDTH=20
HOLD=8
STEP=0.33

tick=0
last=""
while pgrep -xq sketchybar; do
  text="$(cat "$CACHE/media-text" 2>/dev/null)"
  [ -z "$text" ] && exit 0
  len=${#text}
  if [ "$len" -le "$WIDTH" ]; then
    shown="$(printf '%-*s' "$WIDTH" "$text")"
  else
    span=$((len - WIDTH))
    t=$((tick % (2 * (span + HOLD))))
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
  if [ "$shown" != "$last" ]; then
    sketchybar --set media label="$shown"
    last="$shown"
  fi
  tick=$((tick + 1))
  sleep "$STEP"
done
