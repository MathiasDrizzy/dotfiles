#!/usr/bin/env bash
# Bluetooth state: dim icon when off, the name of the first connected device (AirPods included) when one is connected.
# shellcheck disable=SC1091
source "$CONFIG_DIR/colors.sh"

command -v blueutil >/dev/null 2>&1 || exit 0
if [ "$(blueutil --power)" != 1 ]; then
  sketchybar --set "$NAME" icon.color="$OVERLAY0" label.drawing=off
  exit 0
fi

name="$(blueutil --connected --format json | jq -r '.[0].name // empty')"
if [ -n "$name" ]; then
  sketchybar --set "$NAME" icon.color="$MAUVE" label="$(cut -d" " -f1-2 <<<"$name")" label.drawing=on
else
  sketchybar --set "$NAME" icon.color="$MAUVE" label.drawing=off
fi
