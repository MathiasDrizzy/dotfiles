#!/usr/bin/env bash
# AeroSpace workspaces. $1 = workspace id, $2 = "refresh" on the one item that drives the whole row.
# Mouse events tint the item under the pointer; dragging one workspace onto another (drag.sh) swaps their windows.
# Every other event refreshes all workspaces in a single SketchyBar call (a call per item showed the old and the new
# focused workspace highlighted at once), showing only the focused and the occupied ones, and animating the ones that
# appear or disappear so the pills next to them glide instead of jumping.
# shellcheck disable=SC1091
source "$CONFIG_DIR/colors.sh"

STATE="$HOME/.cache/sketchybar/spaces"
DRAGGING="$HOME/.cache/sketchybar/dragging"
DRAG_FLAG_MAX_SECONDS=30
SWAPPING="$HOME/.cache/sketchybar/swapping"
PARK=swap-park # empty workspace that holds the focus during a swap
SLOT_WIDTH=26  # keep in step with icon.width in the rc: a fixed icon width ignores the paddings
HIDDEN_ICON=0x00000000
ANIMATION_CURVE=tanh
ANIMATION_FRAMES=6
ANIMATION_SECONDS=0.15

focused="${FOCUSED_WORKSPACE:-$(aerospace list-workspaces --focused)}"

# Swaps the windows of two workspaces. Windows only move while both workspaces are hidden (the focus parks on scratch
# workspaces), so nothing on screen is re-tiled one window at a time; afterwards the focus follows the content that was
# on screen. The bar skips refreshes meanwhile and repaints once at the end.
swap_workspaces() {
  local from="$1" to="$2" id visible="" from_ids to_ids
  from_ids="$(aerospace list-windows --workspace "$from" --format '%{window-id}')"
  to_ids="$(aerospace list-windows --workspace "$to" --format '%{window-id}')"
  touch "$SWAPPING"
  case "$focused" in
  "$from" | "$to")
    visible="$focused"
    aerospace workspace "$PARK"
    ;;
  esac
  for id in $from_ids; do aerospace move-node-to-workspace --window-id "$id" "$to"; done
  for id in $to_ids; do aerospace move-node-to-workspace --window-id "$id" "$from"; done
  case "$visible" in
  "$from") aerospace workspace "$to" ;;
  "$to") aerospace workspace "$from" ;;
  esac
  rm -f "$SWAPPING"
}

# drag.sh owns the pointer from the first pixel of a drag until half a second after the release: neither the click that
# ends the drag nor the hover tints may touch the row meanwhile.
# (A flag older than DRAG_FLAG_MAX_SECONDS is what a crashed drag.sh left behind, not a drag.)
if [ -e "$DRAGGING" ] && [ $(($(date +%s) - $(stat -f %m "$DRAGGING"))) -lt "$DRAG_FLAG_MAX_SECONDS" ]; then
  [ "$2" = swap ] || exit 0
fi

case "$2" in
click)
  "$CONFIG_DIR/plugins/close_popups.sh"
  aerospace workspace "$1"
  exit 0
  ;;
swap)
  swap_workspaces "$1" "$3"
  exit 0
  ;;
esac

case "$SENDER" in
mouse.entered)
  [ "$1" = "$focused" ] || sketchybar --set "$NAME" background.color=0x44cba6f7 icon.color="$TEXT"
  exit 0
  ;;
mouse.exited)
  [ "$1" = "$focused" ] || sketchybar --set "$NAME" background.color="$TRANSPARENT" icon.color="$TEXT"
  exit 0
  ;;
esac
[ "$2" = refresh ] || exit 0
[ -e "$SWAPPING" ] && exit 0

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
