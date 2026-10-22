#!/usr/bin/env bash
# Control Center button: one icon in place of Wi-Fi and Bluetooth, red while Wi-Fi has no address. It never shows text: its
# width is fixed so the panel always opens under it. The color is set only when it changes. Mouse events go to hover.sh.
# shellcheck disable=SC1091
case "$SENDER" in mouse.*) exec "$CONFIG_DIR/plugins/hover.sh" 0xf0313244 0xd91e1e2e ;; esac
source "$CONFIG_DIR/colors.sh"

color="$MAUVE"
iface="$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2; exit}')"
ipconfig getifaddr "${iface:-en0}" >/dev/null 2>&1 || color="$RED"

[ "$(sketchybar --query "$NAME" | jq -r '.icon.color')" = "$color" ] || sketchybar --set "$NAME" icon.color="$color"
