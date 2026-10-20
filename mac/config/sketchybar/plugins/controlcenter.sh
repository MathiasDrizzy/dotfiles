#!/usr/bin/env bash
# Opens macOS Control Center, or closes it when it is already open. The system draws its own menu bar while the panel
# is open, so the bar becomes opaque and full width until the panel closes and the native bar never shows through.
# The pills keep their place. The bar is always topmost: toggling topmost recreates its window and blanks the pills.
# shellcheck disable=SC1091
source "$CONFIG_DIR/colors.sh"

CTL="$HOME/.local/bin/ctlcenter"
POLL=0.1
MAX_POLLS=1200 # give up after two minutes
SETTLE_POLLS=5 # the panel takes a moment to appear
GRACE_POLLS=6  # the native bar needs a moment to slide away once the pointer leaves

[ -x "$CTL" ] || {
  open "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension"
  exit 0
}

if "$CTL" visible; then
  "$CTL" close
  exit 0
fi

"$CONFIG_DIR/plugins/close_popups.sh"
# The native bar stays up while the pointer is in the top strip, so the cover is kept until the pointer leaves it.
# The pills keep their screen position: the bar loses its 10 px side margin and gains it back as padding.
sketchybar --bar color=0xff11111b margin=0 y_offset=0 height=38 corner_radius=0 padding_left=18 padding_right=34
"$CTL" open

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
sketchybar --bar color="$TRANSPARENT" margin=10 y_offset=4 height=32 corner_radius=12 padding_left=8 padding_right=24
