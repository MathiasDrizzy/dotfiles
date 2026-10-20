#!/usr/bin/env bash
load="$(ps -A -o %cpu | awk '{s+=$1} END {printf "%d", s / '"$(sysctl -n hw.ncpu)"'}')"
sketchybar --set "$NAME" label="${load}%"
