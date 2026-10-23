#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2153
# Now playing (Spotify's only), polled every 5 s and on every now_playing_change: updates the logo and "title  artist" (cut to fit like
# neutonfoo/dotfiles's Spotify item), and slides the pill open when a track loads and closed when none is left.
source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/icons.sh"

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/sketchybar"
BUSY="$CACHE/media_busy"
DIRTY="$CACHE/media_dirty" # the player changed while a slide ran
ITEMS=(media_icon media)
ANIMATION_CURVE=sin
SLIDE_FRAMES=24
TEXT_FRAMES=9
SLIDE_SECONDS=0.45
TEXT_DELAY_SECONDS=0.22
MAX_LENGTH=35                     # characters of title and artist together, at most (fit.sh narrows it so the pill stops short of Vorssaint)
MEDIA_BUNDLE="com.spotify.client" # the pill is Spotify's: a video in a browser tab is "now playing" too
export LC_ALL=en_US.UTF-8         # count characters, not bytes
mkdir -p "$CACHE"
fitted="$(cat "$CACHE/fit_media_chars" 2>/dev/null)"
[ -n "$fitted" ] && [ "$fitted" -lt "$MAX_LENGTH" ] && MAX_LENGTH="$fitted"

# A reload rebuilds the items while this script may be mid-slide: it stops as soon as they are gone, instead of painting
# items that no longer exist ("Item not found" in SketchyBar's log).
alive() { sketchybar --query media_pill >/dev/null 2>&1; }
alive || exit 0

info="$(media-control get 2>/dev/null)"
[ "$(jq -r '.bundleIdentifier // empty' <<<"$info" 2>/dev/null)" = "$MEDIA_BUNDLE" ] || info=""
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

# Closes the pill: the text fades while the widths go to 0, then the items are hidden and stay transparent (SketchyBar
# keeps painting an animating item for a few frames after drawing=off, so visible colors would float).
hide() {
  local item widths args=() fade_out=() slide=()
  alive || exit 0
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
  alive || exit 0
  args=()
  for item in "${ITEMS[@]}"; do args+=(--set "$item" drawing=off width=dynamic); done
  sketchybar "${args[@]}"
}

# Opens the pill from nothing: the items come in at width 0 and transparent, slide to their own widths with the pill, and
# the text fades in once the pill is half open.
show() { # label color, logo color
  local item widths args=() slide=() fade_in=() dynamic=()
  for item in "${ITEMS[@]}"; do
    args+=(--set "$item" drawing=on width=0 icon.color="$TRANSPARENT" label.color="$TRANSPARENT")
    dynamic+=(--set "$item" width=dynamic)
  done
  args+=(--set media_pill background.color="$TRANSPARENT" background.border_color="$TRANSPARENT")
  sketchybar "${args[@]}"
  alive || exit 0
  widths="$(slide_widths "${ITEMS[@]}")" # a drawn item reports the size of its content even at width 0
  for item in "${ITEMS[@]}"; do slide+=(--set "$item" width="$(width_of "$item" "$widths")"); done
  slide+=(--set media_pill background.color="$BAR_COLOR" background.border_color="$BAR_BORDER")
  fade_in+=(--set media_icon icon.color="$2" --set media label.color="$1")
  sketchybar --animate "$ANIMATION_CURVE" "$SLIDE_FRAMES" "${slide[@]}"
  sleep "$TEXT_DELAY_SECONDS"
  alive || exit 0
  sketchybar --animate "$ANIMATION_CURVE" "$TEXT_FRAMES" "${fade_in[@]}"
  sleep "$TEXT_DELAY_SECONDS"
  alive || exit 0
  sketchybar "${dynamic[@]}"
}

# Asked of SketchyBar itself: a state file went stale when a reload rebuilt the items while this script ran.
shown() { [ "$(sketchybar --query media | jq -r '.geometry.drawing')" = on ]; }

if [ -z "$title" ]; then
  shown && hide
  exit 0
fi

# His cut: when both are long each gets half, otherwise the long one gives way to the other.
half=$(((MAX_LENGTH + 1) / 2))
if [ $((${#title} + ${#artist})) -gt "$MAX_LENGTH" ]; then
  if [ "${#title}" -gt "$half" ] && [ "${#artist}" -gt "$half" ]; then
    title="${title:0:$((half - 1))}…"
    artist="${artist:0:$((half - 2))}…"
  elif [ "${#title}" -gt "$half" ]; then
    title="${title:0:$((MAX_LENGTH - ${#artist} - 1))}…"
  elif [ "${#artist}" -gt "$half" ]; then
    artist="${artist:0:$((MAX_LENGTH - ${#title} - 1))}…"
  fi
fi
text="$title"
[ -n "$artist" ] && text="$title $MEDIA_DOT $artist"
if [ "$(sketchybar --query media | jq -r '.label.value')" != "$text" ]; then
  sketchybar --set media label="$text"
fi

# His colors: a green logo while playing, a yellow one while paused.
if [ "$playing" = "true" ]; then
  logo_color="$GREEN"
  label_color="$TEXT"
else
  logo_color="$YELLOW"
  label_color="$OVERLAY0"
fi
if shown; then
  sketchybar --set media_icon icon.color="$logo_color" --set media label.color="$label_color"
else
  show "$label_color" "$logo_color"
fi
# The track is drawn: check it stops short of Vorssaint (fit.sh cuts the next one shorter if it does not).
"$CONFIG_DIR/plugins/fit.sh" right &
