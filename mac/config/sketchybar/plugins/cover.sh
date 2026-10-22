#!/usr/bin/env bash
# The cover (the "cover" bracket of the rc): a full-width picture of the screen strip behind the bar. The system menu bar
# slides down whenever the pointer reaches the top of the screen, and while Control Center or a menu bar extra is open;
# with the cover on it stays hidden under the bar, which still looks like the desktop (the pills keep their place).
#   cover.sh on        shows it
#   cover.sh off       hides it, unless something still needs it: the pointer in the top strip, a Control Center run, or a
#                      panel or menu open (then whoever ends that calls off again)
#   cover.sh settle    waits until nothing needs it any more, then hides it (one waiter at a time)
#   cover.sh remember  refreshes the picture (off does it too, at most every REMEMBER_SECONDS)
#   cover.sh refresh   refreshes the picture when the wallpaper changed since it was taken (the rc runs it every few seconds)
# The bar is always topmost: toggling topmost recreates its window and blanks the pills.
# shellcheck disable=SC1091
source "$CONFIG_DIR/colors.sh"

CTL="$HOME/.local/bin/ctlcenter"
CACHE="$HOME/.cache/sketchybar"
COVER_CACHE="$CACHE/cover"
BACKDROP="$CACHE/cover.png"
BACKDROP_SCALE="$CACHE/cover_scale"
COVER_BUSY="$CACHE/cover_busy"
SETTLER="$CACHE/cover_settler"
DRIVER="$CACHE/cc_driver"
MENU_DRIVER="$CACHE/menu_driver"
COVER_HEIGHT=40 # points: the cover bar is this tall and starts at the top of the screen
FADE_FRAMES=5   # the plain cover fades in and out instead of flashing
REMEMBER_SECONDS=60
WALLPAPER_INDEX="$HOME/Library/Application Support/com.apple.wallpaper/Store/Index.plist" # macOS rewrites it on every change
WALLPAPER_SETTLE_SECONDS=10                                                               # the new picture fades in; one taken before it ends still shows the old desktop
LOCK_TRIES=50
POLL=0.2
SETTLE_POLLS=3 # the native bar needs a moment to slide away once nothing holds it
SETTLE_MAX=600 # give up after two minutes
MENU_DELAY=0.5 # a menu just asked for takes a moment to show

# Keeps a picture of the top of the screen as it looks behind the bar (the bar itself left out), so the next cover looks like
# the desktop; and the average color of the screen's top strip, for the plain cover used without a picture.
remember() {
  local tmp bgra scale
  tmp="$(mktemp -d)" || return
  mkdir -p "$CACHE"
  if scale="$("$CTL" backdrop "$tmp/backdrop.png" "$COVER_HEIGHT" 2>/dev/null)"; then
    mv "$tmp/backdrop.png" "$BACKDROP"
    echo "$scale" >"$BACKDROP_SCALE"
  fi
  if screencapture -x -R0,0,800,3 "$tmp/edge.png" 2>/dev/null &&
    sips -s format bmp -z 1 1 "$tmp/edge.png" --out "$tmp/pixel.bmp" >/dev/null 2>&1; then
    bgra="$(tail -c 4 "$tmp/pixel.bmp" | xxd -p)"
    printf '0xff%s%s%s\n' "${bgra:4:2}" "${bgra:2:2}" "${bgra:0:2}" >"$COVER_CACHE"
  fi
  rm -rf "$tmp"
}

# The picture predates the wallpaper's last change, or was taken while the new one was still fading in.
wallpaper_changed() {
  local changed
  changed="$(stat -f %m "$WALLPAPER_INDEX" 2>/dev/null)" || return 1
  [ ! -s "$BACKDROP" ] || [ $((changed + WALLPAPER_SETTLE_SECONDS)) -gt "$(stat -f %m "$BACKDROP")" ]
}

# The picture when there is one (set again each time, so a new picture is read), else a plain strip in its color. Only the
# cover changes: the bar keeps the rc's geometry, which is the cover's (a resize redrew every pill and the bar shook).
show() {
  local color
  if [ -s "$BACKDROP" ]; then
    sketchybar --set cover drawing=on background.image="$BACKDROP" background.image.drawing=on \
      background.image.scale="$(cat "$BACKDROP_SCALE" 2>/dev/null || echo 0.5)"
  else
    color="$(cat "$COVER_CACHE" 2>/dev/null)"
    sketchybar --set cover drawing=on background.image.drawing=off \
      --animate tanh "$FADE_FRAMES" --set cover background.color="${color:-$CRUST}"
  fi
}

hide() {
  sketchybar --set cover drawing=off background.color="$TRANSPARENT"
}

# Asked of SketchyBar itself: a state file went stale when a reload rebuilt the bar uncovered.
covered() { [ "$(sketchybar --query cover | jq -r '.geometry.drawing')" = on ]; }

needed() {
  "$CTL" top || kill -0 "$(cat "$DRIVER/pid" 2>/dev/null)" 2>/dev/null || kill -0 "$(cat "$MENU_DRIVER/pid" 2>/dev/null)" 2>/dev/null ||
    "$CTL" visible || "$CTL" shown "$MENU_EXTRA_BUNDLE"
}

# on and off one at a time: an off that checked just before the pointer came back would otherwise hide the cover under it.
lock() {
  local _
  for _ in $(seq "$LOCK_TRIES"); do
    mkdir "$COVER_BUSY" 2>/dev/null && return 0
    sleep 0.02
  done
  return 1
}

case "$1" in
on)
  lock || exit 0
  trap 'rmdir "$COVER_BUSY" 2>/dev/null' EXIT
  covered && exit 0
  show
  ;;
off)
  lock || exit 0
  trap 'rmdir "$COVER_BUSY" 2>/dev/null' EXIT
  covered && ! needed || exit 0
  hide
  rmdir "$COVER_BUSY" 2>/dev/null
  trap - EXIT
  if wallpaper_changed || [ -z "$(/usr/bin/find "$BACKDROP" -mtime -"${REMEMBER_SECONDS}s" 2>/dev/null)" ]; then
    sleep 0.4 # let the bar settle before sampling the strip
    remember
  fi
  ;;
settle)
  mkdir "$SETTLER" 2>/dev/null || exit 0
  trap 'rmdir "$SETTLER" 2>/dev/null' EXIT
  sleep "$MENU_DELAY"
  idle=0
  for _ in $(seq "$SETTLE_MAX"); do
    if needed; then idle=0; else idle=$((idle + 1)); fi
    [ "$idle" -ge "$SETTLE_POLLS" ] && break
    sleep "$POLL"
  done
  "$0" off
  ;;
remember) remember ;;
refresh)
  wallpaper_changed || exit 0
  lock || exit 0
  trap 'rmdir "$COVER_BUSY" 2>/dev/null' EXIT
  covered || needed || remember # not while the native bar or the cover is over the strip: they would be in the picture
  ;;
*)
  echo "usage: cover.sh on|off|settle|remember|refresh" >&2
  exit 2
  ;;
esac
