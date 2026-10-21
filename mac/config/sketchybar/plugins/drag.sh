#!/usr/bin/env bash
# Drag a workspace onto another to swap their windows. Runs for the whole session (started by the rc) and follows the
# pointer itself with `ctlcenter watch`, because SketchyBar only reports the end of a drag, never its start or its path.
# While dragging, a ghost pill with the workspace number follows the cursor, the source dims and the workspace under the
# pointer lights up as the drop target. On release the ghost glides into the target slot (or back if nothing was hit).
# shellcheck disable=SC1091
source "$CONFIG_DIR/colors.sh"

DRAGGING="$HOME/.cache/sketchybar/dragging"
PRESS_PANEL="$HOME/.cache/sketchybar/press_panel"
PRESS_MENU="$HOME/.cache/sketchybar/press_menu"
STRIP_HEIGHT=40 # presses that start lower than this are not on the bar
DRAG_THRESHOLD=4
GHOST=drag_ghost
GHOST_HALF_WIDTH=13 # half of the slot width: the ghost is centered on the pointer
SLOT_MARGIN=1       # the gap between two slots belongs to both
RELEASE_GRACE=0.4   # the click that ends the drag must find the flag still there
COVER_GRACE=0.6     # the native bar takes this long to slide away once the pointer leaves the top
ANIMATION_CURVE=tanh
GLIDE_FRAMES=6
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
slot=-1

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

# Sets slot to the index of the slot under x, or -1. (No subshells in the per-pointer-move path: each one costs
# milliseconds, and a ghost that handles fewer moves than arrive falls behind the cursor.)
slot_at() {
  local i
  slot=-1
  for i in "${!ids[@]}"; do
    if [ "$1" -ge $((lefts[i] - SLOT_MARGIN)) ] && [ "$1" -lt $((rights[i] + SLOT_MARGIN)) ]; then
      slot="$i"
      return
    fi
  done
}

start_drag() {
  mode=drag
  touch "$DRAGGING"
  local sid="${ids[$source_slot]}"
  # The ghost is the last item on the left, so its resting position is where the left group ends.
  sketchybar --set "$GHOST" drawing=on padding_left=0 icon="$sid" icon.color="$BASE" background.color="$MAUVE"
  ghost_origin="$(sketchybar --query "$GHOST" | jq -r '.bounding_rects | to_entries[0].value.origin[0]' | cut -d. -f1)"
  sketchybar --set "$GHOST" padding_left=$((lefts[source_slot] - ghost_origin)) \
    --animate "$ANIMATION_CURVE" "$TINT_FRAMES" --set "space.$sid" background.color="$DIM_BACKGROUND" icon.color="$DIM_ICON"
}

follow() {
  local x="$1" hit args=()
  slot_at "$x"
  hit="$slot"
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
  sketchybar --set "$GHOST" padding_left=$((x - GHOST_HALF_WIDTH - ghost_origin)) "${args[@]}"
}

finish_drag() {
  local source_id="${ids[$source_slot]}"
  if [ "$target_slot" -ge 0 ]; then
    local target_id="${ids[$target_slot]}"
    # The ghost lands on the target slot and takes its number: that is where the dragged content lives now.
    sketchybar --animate "$ANIMATION_CURVE" "$GLIDE_FRAMES" --set "$GHOST" padding_left=$((lefts[target_slot] - ghost_origin)) icon="$target_id"
    "$CONFIG_DIR/plugins/aerospace.sh" "$source_id" swap "$target_id"
  else
    sketchybar --animate "$ANIMATION_CURVE" "$GLIDE_FRAMES" --set "$GHOST" padding_left=$((lefts[source_slot] - ghost_origin))
    sleep "$RELEASE_GRACE"
  fi
  # The refresh repaints every slot (the dimmed and the lit ones included) with the focus the swap left.
  sketchybar --set "$GHOST" drawing=off
  rm -f "$DRAGGING"
  sketchybar --trigger aerospace_workspace_change
}

"$HOME/.local/bin/ctlcenter" watch "$STRIP_HEIGHT" "$MENU_EXTRA_BUNDLE" | while read -r event x _ panel menu; do
  case "$event" in
  # The system menu bar slides down while the pointer is at the top of the screen: the cover keeps it hidden.
  top) "$CONFIG_DIR/plugins/cover.sh" on & ;;
  away) { sleep "$COVER_GRACE" && "$CONFIG_DIR/plugins/cover.sh" off; } & ;;
  down)
    pgrep -x sketchybar >/dev/null || exit 0 # SketchyBar is gone: so is the reason to watch
    # macOS closes Control Center and a menu bar extra's menu with the very click that presses their button; the button's
    # script needs to know it was open.
    echo "$panel" >"$PRESS_PANEL"
    echo "$menu" >"$PRESS_MENU"
    mode=idle
    source_slot=-1
    target_slot=-1
    if [ "$x" -lt "$LEFT_COLUMN_LIMIT" ]; then
      load_slots
      slot_at "$x"
      source_slot="$slot"
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
