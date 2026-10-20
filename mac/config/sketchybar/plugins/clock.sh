#!/usr/bin/env bash
# Date and time: "20-10-2026  12:39". Mouse events are handled by hover.sh.
case "$SENDER" in mouse.*) exec "$CONFIG_DIR/plugins/hover.sh" ;; esac

sketchybar --set "$NAME" label="$(date '+%d-%m-%Y  %H:%M')"
