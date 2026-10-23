#!/usr/bin/env bash
# shellcheck disable=SC1091
# Keeps every box of the bar from covering its neighbour or sitting under the camera housing. Measured from the bar itself:
#   left  - the Mac's side: Apple, the front app, the workspace pills and the weather boxes share the strip left of the camera
#           housing. When they do not fit, the front app name narrows first (down to APP_NAME_MIN_WIDTH), then workspaces
#           leave (aerospace.sh draws "+N" for them).
#   right - the track beside the camera housing may only reach Vorssaint: it gets a character budget (media.sh cuts to it).
# `fit.sh` alone does both. Called by the plugins whose content changes a width; a call that finds another one running leaves
# a note and the running one goes round once more, so the last change is always the one fitted.
source "$CONFIG_DIR/colors.sh"

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/sketchybar"
LOCK="$CACHE/fit_busy"
AGAIN="$CACHE/fit_again"
SLOTS="$CACHE/fit_slots"             # workspace slots that fit (absent: all)
NATURAL="$CACHE/fit_natural"         # slots the workspaces would use without a cap (aerospace.sh)
NAME_W="$CACHE/fit_name_w"           # width of the front app name
MEDIA_CHARS="$CACHE/fit_media_chars" # characters of title and artist the track may use (media.sh)
SLOT_STEP=28                         # a workspace slot: its 26 points plus 1 of padding on each side
SPARE_FOR_MORE=28                    # the "+N" marker a capped pill shows
CHAR_WIDTH_TENTHS=72                 # JetBrains Mono at TEXT_SIZE 12: 7.2 points a character, in tenths
MEDIA_OVERHEAD=50                    # the Spotify logo, its paddings and the end padding of the track box
MEDIA_MIN_CHARS=8
MEDIA_MAX_CHARS=35
mkdir -p "$CACHE"

mkdir "$LOCK" 2>/dev/null || {
  touch "$AGAIN"
  exit 0
}
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

# "origin width" of a box that is drawn, nothing otherwise.
box() {
  sketchybar --query "$1" 2>/dev/null | jq -r '
    select(.geometry.drawing == "on") | (.bounding_rects | to_entries[0].value) | select(.size[0] > 0)
    | "\(.origin[0] | floor) \(.size[0] | floor)"'
}
right_edge() {
  local o w
  read -r o w <<<"$(box "$1")"
  [ -n "$o" ] && echo $((o + w))
}
left_edge() {
  local o w
  read -r o w <<<"$(box "$1")"
  [ -n "$o" ] && echo "$o"
}

fit_left() {
  local natural name_now right moon flex fixed want_name cap shown b
  natural="$(cat "$NATURAL" 2>/dev/null)"
  [ -n "$natural" ] || return 0
  name_now="$(cat "$NAME_W" 2>/dev/null)"
  [ -n "$name_now" ] || name_now="$APP_NAME_WIDTH"

  # The right edge of the last box on the left, and the left edge of the first box of the weather group.
  right=""
  for b in ext_spaces spaces front_pill apple; do
    right="$(right_edge "$b")"
    [ -n "$right" ] && break
  done
  moon="$(left_edge weather.moon)"
  [ -n "$moon" ] || moon="$(left_edge weather)"
  [ -n "$right" ] && [ -n "$moon" ] || return 0

  # Everything on the left but the two flexible parts (the name's width and the slots): measured now, then re-spent.
  shown="$(wc -w <"$CACHE/spaces" 2>/dev/null | tr -d ' ')"
  fixed=$((right - name_now - ${shown:-0} * SLOT_STEP))
  flex=$((moon - PILL_GAP - fixed))

  want_name="$APP_NAME_WIDTH"
  cap=""
  if [ "$flex" -lt $((APP_NAME_WIDTH + natural * SLOT_STEP)) ]; then
    want_name=$((flex - natural * SLOT_STEP))
    if [ "$want_name" -lt "$APP_NAME_MIN_WIDTH" ]; then
      want_name="$APP_NAME_MIN_WIDTH"
      cap=$(((flex - want_name - SPARE_FOR_MORE) / SLOT_STEP))
      [ "$cap" -ge 1 ] || cap=1
    fi
  fi

  if [ "$want_name" != "$name_now" ]; then
    echo "$want_name" >"$NAME_W"
    sketchybar --set front_app.name label.width="$want_name"
    # A name that no longer fits slides inside the new width.
    "$CONFIG_DIR/plugins/app_name.sh" "$(sketchybar --query front_app.name | jq -r '.label.value')" >/dev/null 2>&1 &
  fi
  if [ "$cap" != "$(cat "$SLOTS" 2>/dev/null)" ]; then
    if [ -n "$cap" ]; then echo "$cap" >"$SLOTS"; else rm -f "$SLOTS"; fi
    sketchybar --trigger aerospace_workspace_change
  fi
}

fit_right() {
  local width notch_right vorssaint avail chars now
  vorssaint="$(left_edge vorssaint)"
  [ -n "$vorssaint" ] || return 0
  width="$(sketchybar --query displays | jq -r 'map(select(.frame.x == 0 and .frame.y == 0)) | .[0].frame.w | floor')"
  [ -n "$width" ] && [ "$width" != null ] || return 0
  notch_right=$(((width + NOTCH_WIDTH) / 2))
  avail=$((vorssaint - PILL_GAP - notch_right - MEDIA_OVERHEAD))
  chars=$((avail * 10 / CHAR_WIDTH_TENTHS))
  [ "$chars" -le "$MEDIA_MAX_CHARS" ] || chars="$MEDIA_MAX_CHARS"
  [ "$chars" -ge "$MEDIA_MIN_CHARS" ] || chars="$MEDIA_MIN_CHARS"
  now="$(cat "$MEDIA_CHARS" 2>/dev/null)"
  if [ "$now" != "$chars" ]; then
    echo "$chars" >"$MEDIA_CHARS"
    "$CONFIG_DIR/plugins/media.sh" >/dev/null 2>&1 &
  fi
}

while :; do
  rm -f "$AGAIN"
  case "${1:-all}" in
  left) fit_left ;;
  right) fit_right ;;
  *)
    fit_left
    fit_right
    ;;
  esac
  [ -e "$AGAIN" ] || break
done
exit 0
