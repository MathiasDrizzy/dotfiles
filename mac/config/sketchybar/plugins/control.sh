#!/usr/bin/env bash
# Control Center button: one icon in place of Wi-Fi and Bluetooth, red while Wi-Fi has no address. It never shows text: its
# width is fixed so the panel always opens under it. The color is set only when it changes. Mouse events go to hover.sh.
# shellcheck disable=SC1091
source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/helpers.sh"
case "$SENDER" in mouse.*) exec "$CONFIG_DIR/plugins/hover.sh" "$BAR_HOVER" "$BAR_COLOR" ;; esac

color="$MAUVE"
iface="$(bounded 3 networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2; exit}')"
bounded 3 ipconfig getifaddr "${iface:-en0}" >/dev/null 2>&1 || color="$RED"

[ "$(sketchybar --query "$NAME" | jq -r '.icon.color')" = "$color" ] || sketchybar --set "$NAME" icon.color="$color"
