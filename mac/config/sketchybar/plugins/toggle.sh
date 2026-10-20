#!/usr/bin/env bash
# shellcheck disable=SC1091
# Expands or collapses the status items; the chevron points toward where they will go.
# The items fade in and out at their final size: squeezing their width made the labels pile up on each other.
source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/icons.sh"

ITEMS=(sys sys_mem control battery) # the content
PILLS=(sys_pill control battery)    # what has the glass background (the bracket is shown and hidden with its items)
ANIMATION_CURVE=sin
ANIMATION_FRAMES=22
ANIMATION_SECONDS=0.45

color_of() { sketchybar --query "$1" | jq -r ".$2.color"; }

state="$(sketchybar --query sys | jq -r '.geometry.drawing')"

faded=()
shown=()
for item in "${ITEMS[@]}"; do
  icon_color="$(color_of "$item" icon)"
  label_color="$(color_of "$item" label)"
  faded+=(--set "$item" icon.color="$TRANSPARENT" label.color="$TRANSPARENT")
  shown+=(--set "$item" icon.color="$icon_color" label.color="$label_color")
done
for pill in "${PILLS[@]}"; do
  faded+=(--set "$pill" background.color="$TRANSPARENT" background.border_color="$TRANSPARENT")
  shown+=(--set "$pill" background.color="$BAR_COLOR" background.border_color="$BAR_BORDER")
done

if [ "$state" = "on" ]; then
  # Collapse: fade out, then hide and give every color its real value back for the next expansion.
  sketchybar --animate "$ANIMATION_CURVE" "$ANIMATION_FRAMES" "${faded[@]}" --set chevron icon="$CHEVRON_LEFT"
  sleep "$ANIMATION_SECONDS"
  args=()
  for item in "${ITEMS[@]}" sys_pill; do args+=(--set "$item" drawing=off); done
  sketchybar "${args[@]}" "${shown[@]}"
else
  # Expand: show the items already transparent in the same call, then fade them to their real look.
  args=()
  for item in "${ITEMS[@]}" sys_pill; do args+=(--set "$item" drawing=on); done
  sketchybar "${args[@]}" "${faded[@]}" --animate "$ANIMATION_CURVE" "$ANIMATION_FRAMES" "${shown[@]}" --set chevron icon="$CHEVRON_RIGHT"
fi
