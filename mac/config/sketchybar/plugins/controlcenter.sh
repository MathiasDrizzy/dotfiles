#!/usr/bin/env bash
# Opens macOS Control Center, or closes it when it is already open (fn+C toggles it). The system draws its own menu bar
# while the panel is open, so until the panel closes the bar shows a full-width picture of the wallpaper strip behind it
# (the "cover" bracket of the rc) and the native bar never shows through. The pills keep their place.
# The bar is always topmost: toggling topmost recreates its window and blanks the pills.
# shellcheck disable=SC1091
source "$CONFIG_DIR/colors.sh"

CTL="$HOME/.local/bin/ctlcenter"
COVER_CACHE="$HOME/.cache/sketchybar/cover"
BACKDROP="$HOME/.cache/sketchybar/cover.png"
BACKDROP_SCALE="$HOME/.cache/sketchybar/cover_scale"
COVER_HEIGHT=40 # points: the cover bar is this tall and starts at the top of the screen
PRESS_PANEL="$HOME/.cache/sketchybar/press_panel"
PRESS_MAX_SECONDS=2
POLL=0.1
MAX_POLLS=1200   # give up after two minutes
FADE_FRAMES=5    # the bar fades in and out instead of flashing
QUIET_POLLS=2    # no click for this long: the clicking is over
STEADY_POLLS=4   # the panel has not changed for this long: its animation is over
KEY_WAIT_POLLS=8 # a key's effect shows within this long
MAX_KEYS=2
INTENT="$HOME/.cache/sketchybar/cc_intent"
DRIVER="$HOME/.cache/sketchybar/cc_driver"
GRACE_POLLS=6 # the native bar needs a moment to slide away once the pointer leaves

# Keeps a picture of the top of the screen as it looks behind the bar (the bar itself left out), so the next cover looks like
# the desktop; and the average color of the screen's top strip, for the plain cover used without a picture.
remember_cover() {
  local tmp bgra scale
  tmp="$(mktemp -d)" || return
  mkdir -p "$(dirname "$COVER_CACHE")"
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

# Cover on: the picture when there is one (set again each time, so a new picture is read), else a plain bar in its color.
show_cover() {
  if [ -s "$BACKDROP" ]; then
    sketchybar --bar margin=0 y_offset=0 height="$COVER_HEIGHT" corner_radius=0 padding_left=0 padding_right=0 \
      --set cover_left width=18 --set cover_right width=34 \
      --set cover drawing=on background.image="$BACKDROP" background.image.scale="$(cat "$BACKDROP_SCALE" 2>/dev/null || echo 0.5)"
  else
    sketchybar --animate tanh "$FADE_FRAMES" --bar color="$1" margin=0 y_offset=0 height="$COVER_HEIGHT" corner_radius=0 \
      padding_left=18 padding_right=34
  fi
}

# Back to the floating glass bar of the rc.
hide_cover() {
  sketchybar --bar color="$TRANSPARENT" margin=10 y_offset=4 height=32 corner_radius=12 padding_left=8 padding_right=24 \
    --set cover_left width=0 --set cover_right width=0 --set cover drawing=off
}

if [ "$1" = --remember-cover ]; then
  remember_cover
  exit 0
fi

[ -x "$CTL" ] || {
  open "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension"
  exit 0
}

# The press that started this click already closed the panel (drag.sh noted it was open). This comes before looking at the
# window, which is still fading out on screen when the click arrives.
press_closed_panel() {
  [ "$(cat "$PRESS_PANEL" 2>/dev/null)" = open ] && [ $(($(date +%s) - $(stat -f %m "$PRESS_PANEL"))) -lt "$PRESS_MAX_SECONDS" ] || return 1
  rm -f "$PRESS_PANEL"
}

# What the clicks asked for, as "open|closed SERIAL"; every change gets a new serial, so the driver acts once per change.
set_intent() {
  local serial
  read -r _ serial <"$INTENT" 2>/dev/null
  echo "$1 $((${serial:-0} + 1))" >"$INTENT"
}

# One script drives the panel and the cover at a time. A click while it runs only changes what is wanted: fast clicks
# used to start a script each, every one pressing fn+C and covering or uncovering the bar on its own.
if ! mkdir "$DRIVER" 2>/dev/null && kill -0 "$(cat "$DRIVER/pid" 2>/dev/null)" 2>/dev/null; then
  if press_closed_panel || [ "$(cut -d' ' -f1 "$INTENT" 2>/dev/null)" = open ]; then set_intent closed; else set_intent open; fi
  exit 0
fi
echo $$ >"$DRIVER/pid"
trap 'rm -f "$DRIVER/pid"; rmdir "$DRIVER" 2>/dev/null' EXIT

press_closed_panel && exit 0
if "$CTL" visible; then # opened some other way (fn+C): this click closes it
  "$CTL" open
  exit 0
fi

cover="$(cat "$COVER_CACHE" 2>/dev/null)"
cover="${cover:-0xff11111b}"
set_intent open
"$CONFIG_DIR/plugins/close_popups.sh" &
# The native bar stays up while the pointer is in the top strip, so the cover is kept until the pointer leaves it.
show_cover "$cover"

# Makes the panel match the intent with as few fn+C as possible, and never while Control Center is changing: a key that
# landed mid-animation, or among fast clicks, left an empty panel window on screen that no key or click would close.
# A key goes out once the clicks have stopped for QUIET_POLLS and the panel has looked the same for STEADY_POLLS, and gets
# KEY_WAIT_POLLS to take effect (MAX_KEYS per change). A panel the user closes elsewhere ends it.
polls=0
away=0
handled=""
since=0
changed_at=0
pressed_at=-100
keys=0
seen=false
was=false
while [ "$polls" -lt "$MAX_POLLS" ]; do
  read -r intent serial <"$INTENT"
  visible=false
  "$CTL" visible && visible=true
  if [ "$visible" != "$was" ]; then
    was="$visible"
    changed_at="$polls"
  fi
  if [ "$serial" != "$handled" ]; then
    handled="$serial"
    since="$polls"
    keys=0
    seen=false
  fi
  [ "$intent" = open ] && $visible && seen=true
  wanted=false
  [ "$intent" = open ] && wanted=true
  if [ "$wanted" != "$visible" ]; then
    if [ "$intent" = open ] && { $seen || [ "$keys" -ge "$MAX_KEYS" ]; }; then
      set_intent closed # closed by a click elsewhere, or it does not open
      continue
    fi
    if [ $((polls - since)) -ge "$QUIET_POLLS" ] && [ $((polls - changed_at)) -ge "$STEADY_POLLS" ] &&
      [ $((polls - pressed_at)) -ge "$KEY_WAIT_POLLS" ] && [ "$keys" -lt "$MAX_KEYS" ]; then
      "$CTL" open
      pressed_at="$polls"
      keys=$((keys + 1))
    fi
  fi
  if [ "$intent" = closed ] && ! $visible && ! "$CTL" top; then
    away=$((away + 1))
    [ "$away" -ge "$GRACE_POLLS" ] && break
  else
    away=0
  fi
  sleep "$POLL"
  polls=$((polls + 1))
done
wait
hide_cover
sleep 0.4 # let the bar settle before sampling the strip
remember_cover
