#!/usr/bin/env bash
# shellcheck disable=SC1091
# Expands or collapses the status items; the chevron points toward where they will go.
# The items grow from nothing (width and colors animate together) so the pills next to them glide instead of jumping.
source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/icons.sh"

ITEMS=(sys sys_mem control battery) # the content
PILLS=(sys_pill control battery)    # what has the glass background
ANIMATION_CURVE=tanh
ANIMATION_FRAMES=8
ANIMATION_SECONDS=0.25
DEFAULT_WIDTH=40

# Last laid-out width of an item (SketchyBar keeps it while the item is hidden).
width_of() {
  sketchybar --query "$1" | jq -r '(.bounding_rects // {}) | to_entries[0].value.size[0] // empty' | cut -d. -f1
}
color_of() { sketchybar --query "$1" | jq -r ".$2.color"; }

state="$(sketchybar --query sys | jq -r '.geometry.drawing')"

widths=()
icon_colors=()
label_colors=()
for item in "${ITEMS[@]}"; do
  widths+=("$(width_of "$item")")
  icon_colors+=("$(color_of "$item" icon)")
  label_colors+=("$(color_of "$item" label)")
done

shrunk=()
settled=()
grown=()
index=0
for item in "${ITEMS[@]}"; do
  width="${widths[$index]:-$DEFAULT_WIDTH}"
  shrunk+=(--set "$item" width=0 icon.color="$TRANSPARENT" label.color="$TRANSPARENT")
  grown+=(--set "$item" width="$width" icon.color="${icon_colors[$index]}" label.color="${label_colors[$index]}")
  settled+=(--set "$item" width=dynamic)
  index=$((index + 1))
done
for pill in "${PILLS[@]}"; do
  shrunk+=(--set "$pill" background.color="$TRANSPARENT" background.border_color="$TRANSPARENT")
  grown+=(--set "$pill" background.color="$BAR_COLOR" background.border_color="$BAR_BORDER")
done

if [ "$state" = "on" ]; then
  # Collapse: shrink and fade, then hide and give every property its real value back for the next expansion.
  sketchybar --animate "$ANIMATION_CURVE" "$ANIMATION_FRAMES" "${shrunk[@]}" --set chevron icon="$CHEVRON_LEFT"
  sleep "$ANIMATION_SECONDS"
  args=()
  for item in "${ITEMS[@]}" sys_pill; do args+=(--set "$item" drawing=off); done
  index=0
  for item in "${ITEMS[@]}"; do
    args+=(--set "$item" width=dynamic icon.color="${icon_colors[$index]}" label.color="${label_colors[$index]}")
    index=$((index + 1))
  done
  for pill in "${PILLS[@]}"; do args+=(--set "$pill" background.color="$BAR_COLOR" background.border_color="$BAR_BORDER"); done
  sketchybar "${args[@]}"
else
  # Expand: start squeezed and transparent in the same call that shows the items, then animate to the real look.
  args=()
  for item in "${ITEMS[@]}" sys_pill; do args+=(--set "$item" drawing=on); done
  sketchybar "${args[@]}" "${shrunk[@]}" --animate "$ANIMATION_CURVE" "$ANIMATION_FRAMES" "${grown[@]}" --set chevron icon="$CHEVRON_RIGHT"
  sleep "$ANIMATION_SECONDS"
  sketchybar "${settled[@]}"
fi
