#!/usr/bin/env bash
# The moon phase box (neutonfoo/dotfiles's), worked out here instead of asked of a weather service: the days since a
# known new moon (2000-01-06 18:14 UTC), modulo one synodic month, give one of the eight phases.
# shellcheck disable=SC1091
source "$CONFIG_DIR/icons.sh"

KNOWN_NEW_MOON=947182440 # 2000-01-06 18:14 UTC, in seconds
SYNODIC_MONTH=29.530588853 # days

phase="$(awk -v now="$(date +%s)" -v new="$KNOWN_NEW_MOON" -v month="$SYNODIC_MONTH" 'BEGIN {
  age = ((now - new) / 86400) % month
  printf "%d", int(age / month * 8 + 0.5) % 8
}')"
sketchybar --set "$NAME" icon="${MOON_PHASES[$phase]}"
