#!/usr/bin/env bash
# AeroSpace workspaces. $1 = workspace id, $2 = "refresh" on the one item that drives the whole row.
# Mouse events tint the item under the pointer; dragging one workspace onto another swaps their windows.
# Every other event refreshes all workspaces in a single SketchyBar call (a call per item showed the old and the new
# focused workspace highlighted at once), showing only the focused and the occupied ones, and animating the ones that
# appear or disappear so the pills next to them glide instead of jumping.
# shellcheck disable=SC1091
source "$CONFIG_DIR/colors.sh"

STATE="$HOME/.cache/sketchybar/spaces"
HOVER="$HOME/.cache/sketchybar/space_hover"
SLOT_WIDTH=26 # keep in step with icon.width in the rc: a fixed icon width ignores the paddings
HIDDEN_ICON=0x00000000
ANIMATION_CURVE=tanh
ANIMATION_FRAMES=6
DROP_FRAMES=4
DROP=0x99cba6f7
ANIMATION_SECONDS=0.15

focused="${FOCUSED_WORKSPACE:-$(aerospace list-workspaces --focused)}"

# Swaps the windows of two workspaces and keeps the focus on the same content.
swap_workspaces() {
  local from="$1" to="$2" id
  local from_ids to_ids
  from_ids="$(aerospace list-windows --workspace "$from" --format '%{window-id}')"
  to_ids="$(aerospace list-windows --workspace "$to" --format '%{window-id}')"
  for id in $from_ids; do aerospace move-node-to-workspace --window-id "$id" "$to"; done
  for id in $to_ids; do aerospace move-node-to-workspace --window-id "$id" "$from"; done
  case "$focused" in
  "$from") aerospace workspace "$to" ;;
  "$to") aerospace workspace "$from" ;;
  esac
}

# The click script also runs when a drag is released: if the pointer sits on another workspace, that is the swap target.
if [ "$2" = click ]; then
  target="$(cat "$HOVER" 2>/dev/null)"
  if [ -n "$target" ] && [ "$target" != "$1" ]; then
    swap_workspaces "$1" "$target"
    : >"$HOVER"
    # Repaint now instead of waiting for the next tick, so the swap reads as one move.
    sketchybar --trigger aerospace_workspace_change
  else
    "$CONFIG_DIR/plugins/close_popups.sh"
    aerospace workspace "$1"
  fi
  exit 0
fi

case "$SENDER" in
mouse.entered)
  echo "$1" >"$HOVER"
  if "$HOME/.local/bin/ctlcenter" pressed 2>/dev/null; then
    # A drag is on: the workspace under the pointer lights up as the drop target.
    sketchybar --animate "$ANIMATION_CURVE" "$DROP_FRAMES" --set "$NAME" background.color="$DROP" icon.color="$BASE"
  elif [ "$1" != "$focused" ]; then
    sketchybar --set "$NAME" background.color=0x44cba6f7 icon.color="$TEXT"
  fi
  exit 0
  ;;
mouse.exited)
  [ "$(cat "$HOVER" 2>/dev/null)" = "$1" ] && : >"$HOVER"
  [ "$1" = "$focused" ] || sketchybar --animate "$ANIMATION_CURVE" "$DROP_FRAMES" --set "$NAME" background.color="$TRANSPARENT" icon.color="$TEXT"
  exit 0
  ;;
esac
[ "$2" = refresh ] || exit 0

mkdir -p "$(dirname "$STATE")"
previous=" $(cat "$STATE" 2>/dev/null) "
shown=""
now=()
appear=()
vanish=()
occupied=" $(aerospace list-windows --all --format '%{workspace}' 2>/dev/null | sort -u | tr '\n' ' ') "
for sid in $(aerospace list-workspaces --all); do
  case "$occupied" in *" $sid "*) count=1 ;; *) count=0 ;; esac
  if [ "$sid" = "$focused" ]; then
    now+=(--set "space.$sid" background.color="$MAUVE" icon.color="$BASE")
  elif [ "${count:-0}" -gt 0 ]; then
    now+=(--set "space.$sid" background.color="$TRANSPARENT" icon.color="$TEXT")
  else
    case "$previous" in *" $sid "*) vanish+=("$sid") ;; esac
    continue
  fi
  shown="$shown $sid"
  case "$previous" in *" $sid "*) ;; *) appear+=("$sid") ;; esac
done
printf '%s\n' "$shown" >"$STATE"

# New items start squeezed and transparent, then grow; vanishing ones shrink and are dropped once the animation ends.
squeeze=()
grow=()
for sid in "${appear[@]}"; do
  squeeze+=(--set "space.$sid" drawing=on icon.width=0 icon.color="$HIDDEN_ICON")
  grow+=(--set "space.$sid" icon.width="$SLOT_WIDTH")
done
shrink=()
for sid in "${vanish[@]}"; do
  shrink+=(--set "space.$sid" icon.width=0 icon.color="$HIDDEN_ICON" background.color="$TRANSPARENT")
done

# One call: the squeeze is instant, the colors and sizes animate together so the old and the new focus cross-fade.
sketchybar "${squeeze[@]}" --animate "$ANIMATION_CURVE" "$ANIMATION_FRAMES" "${now[@]}" "${grow[@]}" "${shrink[@]}"
if [ "${#shrink[@]}" -gt 0 ]; then
  sleep "$ANIMATION_SECONDS"
  # Hide only what is still gone: another refresh may have brought the workspace back meanwhile.
  current=" $(cat "$STATE" 2>/dev/null) "
  drop=()
  for sid in "${vanish[@]}"; do
    case "$current" in *" $sid "*) ;; *) drop+=(--set "space.$sid" drawing=off icon.width="$SLOT_WIDTH") ;; esac
  done
  [ "${#drop[@]}" -gt 0 ] && sketchybar "${drop[@]}"
fi
exit 0
