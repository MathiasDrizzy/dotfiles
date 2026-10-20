#!/usr/bin/env bash
# Opens macOS Control Center, or closes it when it is already open (fn+C toggles it). The system draws its own menu bar
# while the panel is open, so the bar becomes an opaque full-width cover in the color of the desktop strip behind it
# until the panel closes, and the native bar never shows through. The pills keep their place.
# The bar is always topmost: toggling topmost recreates its window and blanks the pills.
# shellcheck disable=SC1091
source "$CONFIG_DIR/colors.sh"

CTL="$HOME/.local/bin/ctlcenter"
COVER_CACHE="$HOME/.cache/sketchybar/cover"
PRESS_PANEL="$HOME/.cache/sketchybar/press_panel"
PRESS_MAX_SECONDS=2
POLL=0.1
MAX_POLLS=1200 # give up after two minutes
FADE_FRAMES=5  # the bar fades in and out instead of flashing
SETTLE_POLLS=5 # the panel takes a moment to appear
GRACE_POLLS=6  # the native bar needs a moment to slide away once the pointer leaves

# Samples the desktop strip above the pills, so the next cover blends with the wallpaper instead of looking gray.
remember_cover() {
  local tmp bgra
  tmp="$(mktemp -d)" || return
  if screencapture -x -R0,0,800,3 "$tmp/strip.png" 2>/dev/null &&
    sips -s format bmp -z 1 1 "$tmp/strip.png" --out "$tmp/pixel.bmp" >/dev/null 2>&1; then
    bgra="$(tail -c 4 "$tmp/pixel.bmp" | xxd -p)"
    mkdir -p "$(dirname "$COVER_CACHE")"
    printf '0xff%s%s%s\n' "${bgra:4:2}" "${bgra:2:2}" "${bgra:0:2}" >"$COVER_CACHE"
  fi
  rm -rf "$tmp"
}

if [ "$1" = --remember-cover ]; then
  remember_cover
  exit 0
fi

[ -x "$CTL" ] || {
  open "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension"
  exit 0
}

if "$CTL" visible; then
  "$CTL" open
  exit 0
fi
# The press that started this click closes the panel before the click arrives (drag.sh noted it was open): do not reopen it.
if [ "$(cat "$PRESS_PANEL" 2>/dev/null)" = open ] && [ $(($(date +%s) - $(stat -f %m "$PRESS_PANEL"))) -lt "$PRESS_MAX_SECONDS" ]; then
  rm -f "$PRESS_PANEL"
  exit 0
fi

cover="$(cat "$COVER_CACHE" 2>/dev/null)"
cover="${cover:-0xff11111b}"
"$CTL" open &
"$CONFIG_DIR/plugins/close_popups.sh" &
# The native bar stays up while the pointer is in the top strip, so the cover is kept until the pointer leaves it.
# The pills keep their screen position: the bar loses its 10 px side margin and gains it back as padding.
sketchybar --animate tanh "$FADE_FRAMES" --bar color="$cover" margin=0 y_offset=0 height=40 corner_radius=0 padding_left=18 padding_right=34
wait

polls=0
away=0
while [ "$polls" -lt "$MAX_POLLS" ]; do
  sleep "$POLL"
  polls=$((polls + 1))
  if [ "$polls" -gt "$SETTLE_POLLS" ] && ! "$CTL" visible && ! "$CTL" top; then
    away=$((away + 1))
    [ "$away" -ge "$GRACE_POLLS" ] && break
  else
    away=0
  fi
done
sketchybar --animate tanh "$FADE_FRAMES" --bar color="$TRANSPARENT" margin=10 y_offset=4 height=32 corner_radius=12 padding_left=8 padding_right=24
sleep 0.4 # let the cover fade out before sampling the strip
remember_cover
