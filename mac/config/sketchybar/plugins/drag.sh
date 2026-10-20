#!/usr/bin/env bash
# Drag a workspace onto another to swap their windows. Runs for the whole session (started by the rc) and follows the
# pointer itself with `ctlcenter watch`, because SketchyBar only reports the end of a drag, never its start or its path.
# While dragging, a ghost pill with the workspace number follows the cursor, the source dims and the workspace under the
# pointer lights up as the drop target. On release the ghost glides into the target slot (or back if nothing was hit).
# shellcheck disable=SC1091
source "$CONFIG_DIR/colors.sh"

DRAGGING="$HOME/.cache/sketchybar/dragging"
PRESS_PANEL="$HOME/.cache/sketchybar/press_panel"
STRIP_HEIGHT=40 # presses that start lower than this are not on the bar
DRAG_THRESHOLD=4
GHOST=drag_ghost
GHOST_HALF_WIDTH=13 # half of the slot width: the ghost is centered on the pointer
SLOT_MARGIN=1       # the gap between two slots belongs to both
RELEASE_GRACE=0.4   # the click that ends the drag must find the flag still there
ANIMATION_CURVE=tanh
GLIDE_FRAMES=8
TINT_FRAMES=4
DIM_ICON=0x66cdd6f4
DIM_BACKGROUND=0x33cba6f7
TARGET_BACKGROUND=0x99cba6f7
LEFT_COLUMN_LIMIT=700 # workspaces live well left of this; a press further right cannot start a drag

trap 'rm -f "$DRAGGING"' EXIT

ids=()
lefts=()
rights=()
source_slot=-1
target_slot=-1
down_x=0
mode=idle
ghost_origin=0

# Reads every visible workspace with its horizontal span, in one pass.
load_slots() {
  ids=()
  lefts=()
  rights=()
  local sid drawing left width
  while IFS=$'\t' read -r sid drawing left width; do
    [ "$drawing" = on ] || continue
    ids+=("$sid")
    lefts+=("${left%.*}")
    rights+=($((${left%.*} + ${width%.*})))
  done < <(for sid in $(aerospace list-workspaces --all); do
    sketchybar --query "space.$sid" | jq -r --arg sid "$sid" \
      '[$sid, .geometry.drawing, (.bounding_rects | to_entries[0].value | .origin[0], .size[0])] | @tsv'
  done)
}

# Index of the slot under x, or -1.
slot_at() {
  local i
  for i in "${!ids[@]}"; do
    if [ "$1" -ge $((lefts[i] - SLOT_MARGIN)) ] && [ "$1" -lt $((rights[i] + SLOT_MARGIN)) ]; then
      echo "$i"
      return
    fi
  done
  echo -1
}

ghost_padding() { echo $(($1 - GHOST_HALF_WIDTH - ghost_origin)); }

start_drag() {
  mode=drag
  touch "$DRAGGING"
  local sid="${ids[$source_slot]}"
  # The ghost is the last item on the left, so its resting position is where the left group ends.
  sketchybar --set "$GHOST" drawing=on padding_left=0 icon="$sid" icon.color="$BASE" background.color="$MAUVE"
  ghost_origin="$(sketchybar --query "$GHOST" | jq -r '.bounding_rects | to_entries[0].value.origin[0]' | cut -d. -f1)"
  sketchybar --set "$GHOST" padding_left="$(ghost_padding $((lefts[source_slot] + GHOST_HALF_WIDTH)))" \
    --animate "$ANIMATION_CURVE" "$TINT_FRAMES" --set "space.$sid" background.color="$DIM_BACKGROUND" icon.color="$DIM_ICON"
}

follow() {
  local x="$1" hit args=()
  hit="$(slot_at "$x")"
  [ "$hit" = "$source_slot" ] && hit=-1
  if [ "$hit" != "$target_slot" ]; then
    if [ "$target_slot" -ge 0 ]; then
      args+=(--animate "$ANIMATION_CURVE" "$TINT_FRAMES" --set "space.${ids[$target_slot]}" background.color="$TRANSPARENT" icon.color="$TEXT")
    fi
    if [ "$hit" -ge 0 ]; then
      args+=(--animate "$ANIMATION_CURVE" "$TINT_FRAMES" --set "space.${ids[$hit]}" background.color="$TARGET_BACKGROUND" icon.color="$BASE")
    fi
    target_slot="$hit"
  fi
  sketchybar --set "$GHOST" padding_left="$(ghost_padding "$x")" "${args[@]}"
}

finish_drag() {
  local source_id="${ids[$source_slot]}" slot_center
  if [ "$target_slot" -ge 0 ]; then
    local target_id="${ids[$target_slot]}"
    slot_center=$((lefts[target_slot] + GHOST_HALF_WIDTH))
    # The ghost lands on the target slot and takes its number: that is where the dragged content lives now.
    sketchybar --animate "$ANIMATION_CURVE" "$GLIDE_FRAMES" --set "$GHOST" padding_left="$(ghost_padding "$slot_center")" icon="$target_id"
    "$CONFIG_DIR/plugins/aerospace.sh" "$source_id" swap "$target_id"
  else
    slot_center=$((lefts[source_slot] + GHOST_HALF_WIDTH))
    sketchybar --animate "$ANIMATION_CURVE" "$GLIDE_FRAMES" --set "$GHOST" padding_left="$(ghost_padding "$slot_center")"
    sleep "$RELEASE_GRACE"
  fi
  # The refresh repaints every slot (the dimmed and the lit ones included) with the focus the swap left.
  sketchybar --set "$GHOST" drawing=off
  rm -f "$DRAGGING"
  sketchybar --trigger aerospace_workspace_change
}

"$HOME/.local/bin/ctlcenter" watch "$STRIP_HEIGHT" | while read -r event x _ panel; do
  pgrep -x sketchybar >/dev/null || exit 0
  case "$event" in
  down)
    # macOS closes Control Center with the very click that presses its button; the button's script needs to know it was open.
    echo "$panel" >"$PRESS_PANEL"
    mode=idle
    source_slot=-1
    target_slot=-1
    if [ "$x" -lt "$LEFT_COLUMN_LIMIT" ]; then
      load_slots
      source_slot="$(slot_at "$x")"
      [ "$source_slot" -ge 0 ] && mode=armed
      down_x="$x"
    fi
    ;;
  move)
    case "$mode" in
    armed) [ $((x > down_x ? x - down_x : down_x - x)) -ge "$DRAG_THRESHOLD" ] && start_drag && follow "$x" ;;
    drag) follow "$x" ;;
    esac
    ;;
  up)
    [ "$mode" = drag ] && finish_drag
    mode=idle
    ;;
  esac
done
