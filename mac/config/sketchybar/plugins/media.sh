#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2153
# Now playing, polled every 2 s: updates the buttons and the title, and slides the pill open when a track loads and closed
# when none is left (the same drawer as the right-hand panel). The title itself is animated by marquee.sh, which this
# script starts when needed. The play/pause button shows the action the click will do.
source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/icons.sh"

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/sketchybar"
BUSY="$CACHE/media_busy"
DIRTY="$CACHE/media_dirty" # the player changed while a slide ran
ITEMS=(media_prev media_play media_next media)
BUTTONS=(media_prev media_play media_next)
ANIMATION_CURVE=sin
SLIDE_FRAMES=24
TEXT_FRAMES=9
SLIDE_SECONDS=0.45
TEXT_DELAY_SECONDS=0.22
mkdir -p "$CACHE"

info="$(media-control get 2>/dev/null)"
playing="$(jq -r '.playing // false' <<<"$info" 2>/dev/null)"
title="$(jq -r '.title // empty' <<<"$info" 2>/dev/null)"
artist="$(jq -r '.artist // empty' <<<"$info" 2>/dev/null)"

# One slide at a time (the play button and every now_playing_change run this script too). A run that finds one going marks the
# change, and the running one replays it once done: left to the next poll, a player that quit mid-slide kept the pill up.
if ! mkdir "$BUSY" 2>/dev/null; then
  touch "$DIRTY"
  exit 0
fi
finish() {
  rmdir "$BUSY" 2>/dev/null
  if [ -e "$DIRTY" ]; then
    rm -f "$DIRTY"
    "$0" &
  fi
}
trap finish EXIT

# Closes the drawer: the text fades while the widths go to 0, then the items are hidden and stay transparent (SketchyBar
# keeps painting an animating item for a few frames after drawing=off, so visible colors would float).
hide() {
  local item widths args=() fade_out=() slide=()
  widths="$(slide_widths "${ITEMS[@]}")"
  for item in "${ITEMS[@]}"; do
    args+=(--set "$item" width="$(width_of "$item" "$widths")")
    fade_out+=(--set "$item" icon.color="$TRANSPARENT" label.color="$TRANSPARENT")
    slide+=(--set "$item" width=0)
  done
  slide+=(--set media_pill background.color="$TRANSPARENT" background.border_color="$TRANSPARENT")
  sketchybar "${args[@]}" --animate "$ANIMATION_CURVE" "$TEXT_FRAMES" "${fade_out[@]}" \
    --animate "$ANIMATION_CURVE" "$SLIDE_FRAMES" "${slide[@]}"
  sleep "$SLIDE_SECONDS"
  args=()
  for item in "${ITEMS[@]}"; do args+=(--set "$item" drawing=off width=dynamic); done
  sketchybar "${args[@]}"
}

# Opens the drawer from nothing: the items come in at width 0 and transparent, slide to their own widths with the pill, and
# the text fades in once the drawer is half open.
show() { # label color
  local item widths args=() slide=() fade_in=() dynamic=()
  for item in "${ITEMS[@]}"; do
    args+=(--set "$item" drawing=on width=0 icon.color="$TRANSPARENT" label.color="$TRANSPARENT")
    dynamic+=(--set "$item" width=dynamic)
  done
  args+=(--set media_pill background.color="$TRANSPARENT" background.border_color="$TRANSPARENT")
  sketchybar "${args[@]}"
  widths="$(slide_widths "${ITEMS[@]}")" # a drawn item reports the size of its content even at width 0
  for item in "${ITEMS[@]}"; do slide+=(--set "$item" width="$(width_of "$item" "$widths")"); done
  slide+=(--set media_pill background.color="$BAR_COLOR" background.border_color="$BAR_BORDER")
  for item in "${BUTTONS[@]}"; do fade_in+=(--set "$item" icon.color="$MAUVE"); done
  fade_in+=(--set media label.color="$1")
  sketchybar --animate "$ANIMATION_CURVE" "$SLIDE_FRAMES" "${slide[@]}"
  sleep "$TEXT_DELAY_SECONDS"
  sketchybar --animate "$ANIMATION_CURVE" "$TEXT_FRAMES" "${fade_in[@]}"
  sleep "$TEXT_DELAY_SECONDS"
  sketchybar "${dynamic[@]}"
}

# Asked of SketchyBar itself: a state file went stale when a reload rebuilt the items while this script ran.
shown() { [ "$(sketchybar --query media | jq -r '.geometry.drawing')" = on ]; }

if [ -z "$title" ]; then
  : >"$CACHE/media-text"
  shown && hide
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
sketchybar --set media_play icon="$play_icon"
if shown; then
  sketchybar --set media label.color="$label_color"
else
  show "$label_color"
fi

pidfile="$CACHE/marquee.pid"
if ! { [ -s "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; }; then
  nohup "$CONFIG_DIR/plugins/marquee.sh" >/dev/null 2>&1 &
  echo $! >"$pidfile"
fi
