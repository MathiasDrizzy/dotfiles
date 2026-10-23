#!/usr/bin/env bash
# Vorssaint button: opens the menu of Vorssaint's menu bar extra, or closes it when it is open. The system menu bar is
# hidden, so the extra is pressed through Accessibility, and the cover keeps the native bar (which slides down with the
# menu) under the bar until the menu closes. Starts Vorssaint when it is not running. Mouse events are handled by hover.sh.
# macOS opens the menu under the extra, wherever the hidden menu bar has it, so "vorssaint.sh align" (run by the rc and
# after every press) moves the pill right above it.
# shellcheck disable=SC1091
source "$CONFIG_DIR/colors.sh"

CTL="$HOME/.local/bin/ctlcenter"
BUNDLE="$MENU_EXTRA_BUNDLE"
CACHE="$HOME/.cache/sketchybar"
PRESS_MENU="$CACHE/press_menu"
INTENT="$CACHE/menu_intent"
DRIVER="$CACHE/menu_driver"
PRESS_MAX_SECONDS=2
POLL=0.1
MAX_POLLS=1200   # give up after two minutes
QUIET_POLLS=3    # no click for this long: the clicking is over
STEADY_POLLS=3   # the menu has not changed for this long: its animation is over
KEY_WAIT_POLLS=5 # a press shows within this long
MAX_KEYS=2
FIRST_WAIT=0.35 # a click this soon after the first is part of the same burst
DISMISS_X=8     # an empty spot of the bar, left of the Apple logo
DISMISS_Y=20
GRACE_POLLS=3

PILL_WIDTH=28
SPREAD_ITEMS=(battery date clock) # the items right of this one whose labels widen to make the room it needs

# The labels right of this one widen evenly (from their least widths in colors.sh) so this item's center sits over the
# extra's: the boxes grow a little instead of leaving a gap. An extra right of where the item naturally goes leaves them
# at their least widths.
align() {
  local extra x width current wanted least=() now=() total=0 share item i args=()
  extra="$(osascript -e "tell application \"System Events\" to tell (first process whose bundle identifier is \"$BUNDLE\") to \
get {position, size} of menu bar item 1 of menu bar 2" 2>/dev/null)" || return 0
  IFS=', ' read -r x _ width _ <<<"$extra"
  current="$(sketchybar --query vorssaint | jq -r '.bounding_rects | to_entries[0].value.origin[0] | floor')"
  [ -n "$x" ] && [ -n "$width" ] && [ -n "$current" ] || return 0
  least=("$BATTERY_LABEL_WIDTH" "$DATE_LABEL_WIDTH" "$TIME_LABEL_WIDTH")
  for i in "${!SPREAD_ITEMS[@]}"; do
    now[i]="$(sketchybar --query "${SPREAD_ITEMS[i]}" | jq -r '.label.width')"
    total=$((total + now[i] - least[i]))
  done
  wanted=$((x + width / 2 - PILL_WIDTH / 2))
  total=$((total + current - wanted))
  [ "$total" -lt 0 ] && total=0
  for i in "${!SPREAD_ITEMS[@]}"; do
    share=$((total / ${#SPREAD_ITEMS[@]}))
    [ "$i" -eq 0 ] && share=$((share + total % ${#SPREAD_ITEMS[@]}))
    item="${SPREAD_ITEMS[i]}"
    [ "${now[i]}" = $((least[i] + share)) ] || args+=(--set "$item" label.width=$((least[i] + share)))
  done
  [ ${#args[@]} -eq 0 ] || sketchybar "${args[@]}"
  # Vorssaint moved: the track beside the camera housing may have more or less room now.
  "$CONFIG_DIR/plugins/fit.sh" right
}
if [ "${1:-}" = align ]; then
  align
  exit 0
fi

# The menu was open at the press (drag.sh noted it). A click on the bar does not always close it by itself.
press_saw_menu() {
  [ "$(cat "$PRESS_MENU" 2>/dev/null)" = open ] && [ $(($(date +%s) - $(stat -f %m "$PRESS_MENU"))) -lt "$PRESS_MAX_SECONDS" ] || return 1
  rm -f "$PRESS_MENU"
}

# What the clicks asked for, as "open|closed SERIAL"; every change gets a new serial.
set_intent() {
  local serial
  read -r _ serial <"$INTENT" 2>/dev/null
  echo "$1 $((${serial:-0} + 1))" >"$INTENT"
}

# One script drives the menu at a time; a click while it runs only flips what is wanted. Pressing the extra once per click
# toggled a menu that was still opening or closing, and fast clicks ended in the wrong state.
if ! mkdir "$DRIVER" 2>/dev/null && kill -0 "$(cat "$DRIVER/pid" 2>/dev/null)" 2>/dev/null; then
  if [ "$(cut -d' ' -f1 "$INTENT" 2>/dev/null)" = open ]; then set_intent closed; else set_intent open; fi
  exit 0
fi
echo $$ >"$DRIVER/pid"
trap 'rm -f "$DRIVER/pid"; rmdir "$DRIVER" 2>/dev/null' EXIT

"$CONFIG_DIR/plugins/close_popups.sh" &
align & # the extra moves only when other extras come or go: the next press finds the pill in place
"$CONFIG_DIR/plugins/cover.sh" on
visible=false
"$CTL" shown "$BUNDLE" && visible=true
if press_saw_menu || $visible; then set_intent closed; else set_intent open; fi
read -r _ handled <"$INTENT"

# Makes the menu match the intent: a press goes out once the clicks have stopped for QUIET_POLLS and the menu has looked the
# same for STEADY_POLLS, and gets KEY_WAIT_POLLS to show (MAX_KEYS per change). A menu closed elsewhere ends it. The first
# press waits only for the clicks (FIRST_WAIT; the menu starts still): sent at once, the clicks after it landed on a menu
# still opening. Closing is a click outside the menu, never a press nor Escape: a menu closed either way left Vorssaint so
# that the next menu shut at a click inside it (every other opening). A menu that does not close is taken as open.
sleep "$FIRST_WAIT"
polls=0
since=-"$QUIET_POLLS"
changed_at=-"$STEADY_POLLS"
pressed_at=-"$KEY_WAIT_POLLS"
keys=0
seen=false
was="$visible"
away=0
while [ "$polls" -lt "$MAX_POLLS" ]; do
  read -r intent serial <"$INTENT"
  visible=false
  "$CTL" shown "$BUNDLE" && visible=true
  if [ "$visible" != "$was" ]; then
    was="$visible"
    changed_at="$polls"
  fi
  if [ "$serial" != "$handled" ]; then
    handled="$serial"
    since="$polls"
    keys=0
    seen=false
  fi
  [ "$intent" = open ] && $visible && seen=true
  # Open and settled: the menu is the user's now. A click inside it can redraw its window, and a driver still watching
  # took the blink for a close elsewhere and shut the menu under the pointer. The cover waits for it on its own.
  $seen && [ $((polls - since)) -ge "$QUIET_POLLS" ] && [ $((polls - changed_at)) -ge "$STEADY_POLLS" ] && break
  wanted=false
  [ "$intent" = open ] && wanted=true
  if [ "$wanted" != "$visible" ]; then
    if [ "$intent" = open ] && { $seen || [ "$keys" -ge "$MAX_KEYS" ]; }; then
      set_intent closed # closed by a click elsewhere, or it does not open
      continue
    fi
    if [ "$intent" = closed ] && [ "$keys" -ge "$MAX_KEYS" ] && [ $((polls - pressed_at)) -ge "$KEY_WAIT_POLLS" ]; then
      set_intent open # it stayed open
      continue
    fi
    if [ $((polls - since)) -ge "$QUIET_POLLS" ] && [ $((polls - changed_at)) -ge "$STEADY_POLLS" ] &&
      [ $((polls - pressed_at)) -ge "$KEY_WAIT_POLLS" ] && [ "$keys" -lt "$MAX_KEYS" ]; then
      if [ "$intent" = closed ]; then
        "$CTL" dismiss "$DISMISS_X" "$DISMISS_Y"
      else
        "$CTL" menu "$BUNDLE" || {
          open -b "$BUNDLE" # not running: start it instead
          break
        }
      fi
      pressed_at="$polls"
      keys=$((keys + 1))
    fi
  fi
  if [ "$intent" = closed ] && ! $visible; then
    away=$((away + 1))
    [ "$away" -ge "$GRACE_POLLS" ] && break
  else
    away=0
  fi
  sleep "$POLL"
  polls=$((polls + 1))
done
# Let go first, then hand the cover to its waiter (it comes off once the pointer has left the top as well).
rm -f "$DRIVER/pid"
rmdir "$DRIVER" 2>/dev/null
trap - EXIT
"$CONFIG_DIR/plugins/cover.sh" settle
