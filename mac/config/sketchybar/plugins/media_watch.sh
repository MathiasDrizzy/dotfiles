#!/usr/bin/env bash
# Tells media.sh the moment the player changes (a track loads, playback pauses, the player quits): every update from
# `media-control stream` becomes a now_playing_change event (not SketchyBar's own media_change, which never reaches a
# script on current macOS). Polling every 2 s left the pill up to 2.6 s behind; the poll stays as a fallback. Runs for the
# whole session (started by the rc) and reconnects if the stream ends.
RECONNECT_SECONDS=2

while :; do
  media-control stream 2>/dev/null | while read -r _; do
    sketchybar --trigger now_playing_change
  done
  sleep "$RECONNECT_SECONDS"
done
