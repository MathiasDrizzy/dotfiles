#!/usr/bin/env bash
# AeroSpace workspaces. $1 = workspace id, $2 = "refresh" on the one item that drives the whole row.
# Mouse events tint the item under the pointer. Every other event refreshes all workspaces in a single SketchyBar call
# (a call per item showed the old and the new focused workspace highlighted at once), showing only the focused and the
# occupied ones, and animating the ones that appear or disappear so the pills next to them glide instead of jumping.
# shellcheck disable=SC1091
source "$CONFIG_DIR/colors.sh"

STATE="$HOME/.cache/sketchybar/spaces"
PAD=9
HIDDEN_ICON=0x00000000
ANIMATION_CURVE=tanh
ANIMATION_FRAMES=14
ANIMATION_SECONDS=0.4

focused="${FOCUSED_WORKSPACE:-$(aerospace list-workspaces --focused)}"

case "$SENDER" in
mouse.entered | mouse.exited)
  [ "$1" = "$focused" ] && exit 0
  if [ "$SENDER" = mouse.entered ]; then
    sketchybar --set "$NAME" background.color=0x44cba6f7 icon.color="$TEXT"
  else
    sketchybar --set "$NAME" background.color="$TRANSPARENT" icon.color="$TEXT"
  fi
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
for sid in $(aerospace list-workspaces --all); do
  count="$(aerospace list-windows --workspace "$sid" --count 2>/dev/null || echo 0)"
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
  squeeze+=(--set "space.$sid" drawing=on icon.padding_left=0 icon.padding_right=0 icon.color="$HIDDEN_ICON")
  grow+=(--set "space.$sid" icon.padding_left="$PAD" icon.padding_right="$PAD")
done
shrink=()
for sid in "${vanish[@]}"; do
  shrink+=(--set "space.$sid" icon.padding_left=0 icon.padding_right=0 icon.color="$HIDDEN_ICON" background.color="$TRANSPARENT")
done

# One call: the squeeze is instant, the colors and sizes animate together so the old and the new focus cross-fade.
sketchybar "${squeeze[@]}" --animate "$ANIMATION_CURVE" "$ANIMATION_FRAMES" "${now[@]}" "${grow[@]}" "${shrink[@]}"
if [ "${#shrink[@]}" -gt 0 ]; then
  sleep "$ANIMATION_SECONDS"
  # Hide only what is still gone: another refresh may have brought the workspace back meanwhile.
  current=" $(cat "$STATE" 2>/dev/null) "
  drop=()
  for sid in "${vanish[@]}"; do
    case "$current" in *" $sid "*) ;; *) drop+=(--set "space.$sid" drawing=off icon.padding_left="$PAD" icon.padding_right="$PAD") ;; esac
  done
  [ "${#drop[@]}" -gt 0 ] && sketchybar "${drop[@]}"
fi
exit 0
