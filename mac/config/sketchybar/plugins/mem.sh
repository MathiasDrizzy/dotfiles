#!/usr/bin/env bash
# Memory in use, as a percentage of the free-page accounting from memory_pressure.
free="$(memory_pressure | awk '/free percentage/ {gsub("%","",$NF); print $NF}')"
[ -z "$free" ] && exit 0
sketchybar --set "$NAME" label="$((100 - free))%"
