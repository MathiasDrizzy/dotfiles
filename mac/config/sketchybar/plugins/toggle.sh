#!/usr/bin/env bash
# shellcheck disable=SC1091
# Expands or collapses the status items; the chevron points toward where they will go.
# The items fade in and out at their final size: squeezing their width made the labels pile up on each other.
# Clicks that arrive while it animates are ignored, and the colors it fades to are fixed (never read back from an item that
# is mid-fade), so repeated clicks cannot leave half-transparent icons or numbers behind.
source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/icons.sh"

ITEMS=(sys sys_mem control battery) # the content
PILLS=(sys_pill control battery)    # what has the glass background (the bracket is shown and hidden with its items)
ANIMATION_CURVE=sin
ANIMATION_FRAMES=22
ANIMATION_SECONDS=0.45
STALE_LOCK_SECONDS=3

# One toggle at a time (a lock older than STALE_LOCK_SECONDS is a crashed run, not a busy one).
if [ -e "$PANEL_BUSY" ] && [ $(($(date +%s) - $(stat -f %m "$PANEL_BUSY"))) -lt "$STALE_LOCK_SECONDS" ]; then
  exit 0
fi
mkdir -p "$(dirname "$PANEL_STATE")"
touch "$PANEL_BUSY"
trap 'rm -f "$PANEL_BUSY"' EXIT

faded=()
shown=()
for item in "${ITEMS[@]}"; do
  faded+=(--set "$item" icon.color="$TRANSPARENT" label.color="$TRANSPARENT")
  shown+=(--set "$item" icon.color="$MAUVE" label.color="$TEXT")
done
for pill in "${PILLS[@]}"; do
  faded+=(--set "$pill" background.color="$TRANSPARENT" background.border_color="$TRANSPARENT")
  shown+=(--set "$pill" background.color="$BAR_COLOR" background.border_color="$BAR_BORDER")
done

if [ "$(cat "$PANEL_STATE" 2>/dev/null)" = on ]; then
  # Collapse: fade out, then hide and give every color its real value back for the next expansion.
  sketchybar --animate "$ANIMATION_CURVE" "$ANIMATION_FRAMES" "${faded[@]}" --set chevron icon="$CHEVRON_LEFT"
  sleep "$ANIMATION_SECONDS"
  args=()
  for item in "${ITEMS[@]}" sys_pill; do args+=(--set "$item" drawing=off); done
  sketchybar "${args[@]}" "${shown[@]}"
  echo off >"$PANEL_STATE"
else
  # Expand: show the items already transparent in the same call, then fade them to their real look.
  args=()
  for item in "${ITEMS[@]}" sys_pill; do args+=(--set "$item" drawing=on); done
  sketchybar "${args[@]}" "${faded[@]}" --animate "$ANIMATION_CURVE" "$ANIMATION_FRAMES" "${shown[@]}" --set chevron icon="$CHEVRON_RIGHT"
  sleep "$ANIMATION_SECONDS"
  echo on >"$PANEL_STATE"
  rm -f "$PANEL_BUSY"
  sketchybar --update # the plugins skipped their updates while the panel was hidden
fi
