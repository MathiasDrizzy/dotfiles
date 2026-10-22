#!/usr/bin/env bash
# The date ("21-10-2026") and the time ("22:46"), each in its own box. Mouse events are handled by hover.sh.
# shellcheck disable=SC1091
source "$CONFIG_DIR/colors.sh"
case "$SENDER" in mouse.*) exec "$CONFIG_DIR/plugins/hover.sh" "$BAR_HOVER" "$BAR_COLOR" ;; esac

case "$NAME" in
date) sketchybar --set date label="$(date '+%d-%m-%Y')" ;;
*) sketchybar --set "$NAME" label="$(date '+%H:%M')" ;;
esac
