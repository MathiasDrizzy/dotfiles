#!/usr/bin/env bash
# shellcheck disable=SC1091
case "$SENDER" in mouse.*) exec "$CONFIG_DIR/plugins/hover.sh" 0xf0313244 0xd91e1e2e ;; esac
source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/icons.sh"

iface="$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2; exit}')"
if ipconfig getifaddr "${iface:-en0}" >/dev/null 2>&1; then
  sketchybar --set "$NAME" icon="$WIFI" icon.color="$MAUVE" label.drawing=off
else
  sketchybar --set "$NAME" icon="$WIFI_OFF" icon.color="$RED" label.drawing=off
fi
