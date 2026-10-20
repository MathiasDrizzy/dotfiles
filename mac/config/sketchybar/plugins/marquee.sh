#!/usr/bin/env bash
# Pixel-smooth title marquee for the media item. The label has a fixed width (set in the rc) and clips the text; this
# script slides the text left and right by changing label.padding_left, and grows label.padding_right by the same amount
# so the pill never changes size. It bounces (pausing at both ends) at about 25 px per second. Started by media.sh;
# it exits on its own when there is no track or SketchyBar is gone.
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/sketchybar"
LABEL_WIDTH=144
CHAR_PX_X10=72 # width of one character at 12 pt, times 10
BASE_PAD_RIGHT=10
HOLD=40   # frames to pause at each end
STEP=0.04 # seconds per frame (1 px per frame)
REREAD=25 # frames between reads of the title

frame=0
span=0
last=-1
while pgrep -xq sketchybar; do
  if [ $((frame % REREAD)) -eq 0 ]; then
    length="$(wc -m <"$CACHE/media-text" 2>/dev/null | tr -d ' ')"
    [ "${length:-0}" -eq 0 ] && exit 0
    span=$((length * CHAR_PX_X10 / 10 - LABEL_WIDTH + 8))
  fi
  offset=0
  if [ "$span" -gt 0 ]; then
    t=$((frame % (2 * (span + HOLD))))
    if [ "$t" -lt "$HOLD" ]; then
      offset=0
    elif [ "$t" -lt $((HOLD + span)) ]; then
      offset=$((t - HOLD))
    elif [ "$t" -lt $((2 * HOLD + span)) ]; then
      offset=$span
    else
      offset=$((span - (t - 2 * HOLD - span)))
    fi
  fi
  if [ "$offset" -ne "$last" ]; then
    sketchybar --set media label.padding_left="-$offset" label.padding_right="$((BASE_PAD_RIGHT + offset))"
    last=$offset
  fi
  frame=$((frame + 1))
  sleep "$STEP"
done
