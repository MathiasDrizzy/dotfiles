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
PICK="$HOME/.cache/sketchybar/workspace_pick"
CAP="$HOME/.cache/sketchybar/fit_slots"       # fit.sh: how many workspace slots fit (absent: all)
NATURAL="$HOME/.cache/sketchybar/fit_natural" # how many would show without the cap (for fit.sh)
MAIN_SCREEN=1                                 # AppKit id of the Mac's own screen
SLOT_WIDTH=26                                 # keep in step with icon.width in the rc: a fixed icon width ignores the paddings
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
  touch "$PICK" # asked for: stay.sh must not take the focus back
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
  [ "$1" = "$focused" ] || sketchybar --set "$NAME" background.color="$BAR_HOVER" icon.color="$TEXT"
  exit 0
  ;;
mouse.exited)
  [ "$1" = "$focused" ] || sketchybar --set "$NAME" background.color="$TRANSPARENT" icon.color="$TEXT"
  exit 0
  ;;
esac
[ "$2" = refresh ] || exit 0
[ -e "$SWAPPING" ] && exit 0
# The rc makes the items one by one and this item already ticks: wait until the last one (the other monitor's pill) exists.
sketchybar --query ext_spaces >/dev/null 2>&1 || exit 0

# Two pills: the workspaces of the Mac's own screen (space.N) and of any other monitor (ext.N). The focused workspace is the
# mauve block on the Mac's pill and a blue one on the other; the one a monitor shows without the focus is a lighter box.
# A workspace shows when it is focused, visible on its monitor (even empty) or has windows. fit.sh caps how many slots
# fit beside the weather box; the focused and visible ones always stay, the rest give way (the pill says "+N").
mkdir -p "$(dirname "$STATE")"
previous=" $(cat "$STATE" 2>/dev/null) "
occupied=" $(aerospace list-windows --all --format '%{workspace}' 2>/dev/null | sort -u | tr '\n' ' ') "
cap="$(cat "$CAP" 2>/dev/null)"
[ -n "$cap" ] || cap=99
in_list() {
  case " $2 " in *" $1 "*) return 0 ;; esac
  return 1
}
mac=() mac_must=() ext=() ext_must=()
visible_ids=""
rows="$(aerospace list-workspaces --all --format '%{workspace}|%{monitor-appkit-nsscreen-screens-id}|%{workspace-is-visible}|%{workspace-is-focused}' 2>/dev/null)"
# The external monitor's workspaces (eN) stay on the Mac once it is unplugged: they leave the bar with the monitor, unless one
# has the focus.
external_present=false
while IFS='|' read -r _ monitor _ _; do
  [ -z "$monitor" ] || [ "$monitor" = "$MAIN_SCREEN" ] || external_present=true
done <<<"$rows"
while IFS='|' read -r sid monitor visible is_focused; do
  [ -n "$sid" ] || continue
  [ "$visible" = true ] && visible_ids="$visible_ids $sid"
  must=false
  { [ "$sid" = "$focused" ] || [ "$visible" = true ] || [ "$is_focused" = true ]; } && must=true
  case "$occupied" in *" $sid "*) ;; *) $must || continue ;; esac
  if ! $external_present && [ "$sid" != "$focused" ]; then
    case "$sid" in e[0-9]*) continue ;; esac
  fi
  if [ "$monitor" = "$MAIN_SCREEN" ]; then
    mac+=("$sid")
    $must && mac_must+=("$sid")
  else
    ext+=("$sid")
    $must && ext_must+=("$sid")
  fi
done <<<"$rows"
echo $((${#mac[@]} + ${#ext[@]})) >"$NATURAL"

# Over the cap: the last workspace that is neither focused nor visible leaves, from the pill with more of them.
hidden_mac=0
hidden_ext=0
last_optional() { # workspaces, the ones that must stay: the last of the first that is not among the second
  local sid last=""
  for sid in $1; do in_list "$sid" "$2" || last="$sid"; done
  echo "$last"
}
without() { # workspaces, one to leave out
  local sid out=()
  for sid in $1; do [ "$sid" = "$2" ] || out+=("$sid"); done
  echo "${out[*]}"
}
while [ $((${#mac[@]} + ${#ext[@]})) -gt "$cap" ]; do
  gone_mac="$(last_optional "${mac[*]}" "${mac_must[*]}")"
  gone_ext="$(last_optional "${ext[*]}" "${ext_must[*]}")"
  [ -n "$gone_mac$gone_ext" ] || break
  # The pill with more optional workspaces gives one up (the Mac's on a tie).
  if [ -n "$gone_mac" ] && { [ -z "$gone_ext" ] || [ $((${#mac[@]} - ${#mac_must[@]})) -ge $((${#ext[@]} - ${#ext_must[@]})) ]; }; then
    read -r -a mac <<<"$(without "${mac[*]}" "$gone_mac")"
    hidden_mac=$((hidden_mac + 1))
  else
    read -r -a ext <<<"$(without "${ext[*]}" "$gone_ext")"
    hidden_ext=$((hidden_ext + 1))
  fi
done

shown=""
now=()
appear=()
vanish=()
gone=()   # leave at once: the pill of a monitor that was unplugged
paint() { # item, workspace, pill color
  local item="$1" sid="$2" block="$3"
  if [ "$sid" = "$focused" ]; then
    now+=(--set "$item" background.color="$block" icon.color="$BASE")
  elif in_list "$sid" "$visible_ids"; then
    now+=(--set "$item" background.color="$SURFACE1" icon.color="$TEXT")
  else
    now+=(--set "$item" background.color="$TRANSPARENT" icon.color="$TEXT")
  fi
}
for sid in "${mac[@]}"; do
  paint "space.$sid" "$sid" "$MAUVE"
  shown="$shown space.$sid"
done
for sid in "${ext[@]}"; do
  paint "ext.$sid" "$sid" "$EXT_BLOCK"
  shown="$shown ext.$sid"
done
for item in $shown; do case "$previous" in *" $item "*) ;; *) appear+=("$item") ;; esac done
# What was drawn and no longer is leaves (a workspace that empties out may vanish from AeroSpace's list altogether).
for item in $previous; do
  case "$shown " in *" $item "*) continue ;; esac
  if ! $external_present && [ "${item#ext.}" != "$item" ]; then
    gone+=(--set "$item" drawing=off icon.width="$SLOT_WIDTH" background.color="$TRANSPARENT")
  else
    vanish+=("$item")
  fi
done
printf '%s\n' "$shown" >"$STATE"

# New items start squeezed and transparent, then grow; vanishing ones shrink and are dropped once the animation ends.
squeeze=()
grow=()
for item in "${appear[@]}"; do
  squeeze+=(--set "$item" drawing=on icon.width=0 icon.color="$HIDDEN_ICON")
  grow+=(--set "$item" icon.width="$SLOT_WIDTH")
done
shrink=()
for item in "${vanish[@]}"; do
  shrink+=(--set "$item" icon.width=0 icon.color="$HIDDEN_ICON" background.color="$TRANSPARENT")
done
# The monitor mark, its gap and the "+N" markers follow what is drawn (no animation: they are not workspaces).
extra=()
if [ "${#ext[@]}" -gt 0 ]; then
  extra+=(--set ext_gap drawing=on --set ext.mark drawing=on)
else
  extra+=(--set ext_gap drawing=off --set ext.mark drawing=off)
fi
for side in space ext; do
  hidden="hidden_${side/space/mac}"
  if [ "${!hidden}" -gt 0 ]; then
    extra+=(--set "$side.more" drawing=on icon="+${!hidden}")
  else
    extra+=(--set "$side.more" drawing=off)
  fi
done

# One call: the squeeze is instant, the colors and sizes animate together so the old and the new focus cross-fade.
sketchybar "${gone[@]}" "${squeeze[@]}" "${extra[@]}" --animate "$ANIMATION_CURVE" "$ANIMATION_FRAMES" "${now[@]}" "${grow[@]}" "${shrink[@]}"
if [ "${#shrink[@]}" -gt 0 ]; then
  sleep "$ANIMATION_SECONDS"
  # Hide only what is still gone: another refresh may have brought the workspace back meanwhile.
  current=" $(cat "$STATE" 2>/dev/null) "
  drop=()
  for item in "${vanish[@]}"; do
    case "$current" in *" $item "*) ;; *) drop+=(--set "$item" drawing=off icon.width="$SLOT_WIDTH") ;; esac
  done
  [ "${#drop[@]}" -gt 0 ] && sketchybar "${drop[@]}"
fi
# What is drawn changed: the boxes may no longer fit beside each other (fit.sh).
[ " $shown " = "$previous" ] || "$CONFIG_DIR/plugins/fit.sh" left
exit 0
