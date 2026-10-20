#!/usr/bin/env bash
# Opens macOS Control Center. The system draws its own menu bar while the panel is open, so the bar is made opaque,
# full width and topmost until the panel closes: the native bar never shows through.
# shellcheck disable=SC1091
source "$CONFIG_DIR/colors.sh"

POLL=0.2
MAX_POLLS=600 # give up after two minutes

command -v ctlcenter >/dev/null 2>&1 || {
  open "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension"
  exit 0
}

"$CONFIG_DIR/plugins/close_popups.sh"
sketchybar --bar topmost=on color=0xff11111b margin=0 y_offset=0 height=38 corner_radius=0
ctlcenter open

polls=0
until ! ctlcenter visible && [ "$polls" -gt 3 ]; do
  sleep "$POLL"
  polls=$((polls + 1))
  [ "$polls" -ge "$MAX_POLLS" ] && break
done
sketchybar --bar topmost=off color="$TRANSPARENT" margin=10 y_offset=4 height=32 corner_radius=12
