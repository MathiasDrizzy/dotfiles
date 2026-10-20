#!/usr/bin/env bash
# Control Center button: one icon in place of Wi-Fi and Bluetooth. It turns red when Wi-Fi has no address and shows the
# name of the connected Bluetooth device (AirPods included). Mouse events are handled by hover.sh.
# shellcheck disable=SC1091
case "$SENDER" in mouse.*) exec "$CONFIG_DIR/plugins/hover.sh" 0xf0313244 0xd91e1e2e ;; esac
source "$CONFIG_DIR/colors.sh"

color="$MAUVE"
iface="$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2; exit}')"
ipconfig getifaddr "${iface:-en0}" >/dev/null 2>&1 || color="$RED"

panel_idle || exit 0

device=""
if command -v blueutil >/dev/null 2>&1 && [ "$(blueutil --power)" = 1 ]; then
  device="$(blueutil --connected --format json | jq -r '.[0].name // empty')"
fi

if [ -n "$device" ]; then
  sketchybar --set "$NAME" icon.color="$color" label="$(cut -d" " -f1-2 <<<"$device")" label.drawing=on
else
  sketchybar --set "$NAME" icon.color="$color" label.drawing=off
fi
