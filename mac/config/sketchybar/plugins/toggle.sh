#!/usr/bin/env bash
# shellcheck disable=SC1091
# Expands or collapses the status items; the chevron points toward where they will go.
source "$CONFIG_DIR/icons.sh"

ITEMS=(sys wifi battery)
state="$(sketchybar --query sys | jq -r '.geometry.drawing')"

if [ "$state" = "on" ]; then
  drawing=off
  chevron="$CHEVRON_LEFT"
else
  drawing=on
  chevron="$CHEVRON_RIGHT"
fi

args=()
for item in "${ITEMS[@]}"; do args+=(--set "$item" drawing="$drawing"); done
sketchybar "${args[@]}" --set chevron icon="$chevron"
