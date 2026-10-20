#!/usr/bin/env bash
# Date and time: "20-10-2026  ·  12:39". Mouse events are handled by hover.sh.
case "$SENDER" in mouse.*) exec "$CONFIG_DIR/plugins/hover.sh" 0xf0313244 0xd91e1e2e ;; esac

sketchybar --set "$NAME" label="$(date '+%d-%m-%Y  ·  %H:%M')"
