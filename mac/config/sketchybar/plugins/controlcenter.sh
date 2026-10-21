#!/usr/bin/env bash
# Opens macOS Control Center, or closes it when it is already open (fn+C toggles it). The system draws its own menu bar
# while the panel is open, so until the panel closes the cover (cover.sh) keeps it hidden under the bar.
# shellcheck disable=SC1091
source "$CONFIG_DIR/colors.sh"

CTL="$HOME/.local/bin/ctlcenter"
PRESS_PANEL="$HOME/.cache/sketchybar/press_panel"
PRESS_MAX_SECONDS=2
POLL=0.1
MAX_POLLS=1200   # give up after two minutes
QUIET_POLLS=3    # no click for this long: the clicking is over
STEADY_POLLS=4   # the panel has not changed for this long: its animation is over
KEY_WAIT_POLLS=8 # a key's effect shows within this long
MAX_KEYS=2
FIRST_WAIT=0.35 # a click this soon after the first is part of the same burst
INTENT="$HOME/.cache/sketchybar/cc_intent"
DRIVER="$HOME/.cache/sketchybar/cc_driver"
GRACE_POLLS=6 # the native bar needs a moment to slide away once the pointer leaves

[ -x "$CTL" ] || {
  open "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension"
  exit 0
}

# The press that started this click already closed the panel (drag.sh noted it was open). This comes before looking at the
# window, which is still fading out on screen when the click arrives.
press_closed_panel() {
  [ "$(cat "$PRESS_PANEL" 2>/dev/null)" = open ] && [ $(($(date +%s) - $(stat -f %m "$PRESS_PANEL"))) -lt "$PRESS_MAX_SECONDS" ] || return 1
  rm -f "$PRESS_PANEL"
}

# What the clicks asked for, as "open|closed SERIAL"; every change gets a new serial, so the driver acts once per change.
set_intent() {
  local serial
  read -r _ serial <"$INTENT" 2>/dev/null
  echo "$1 $((${serial:-0} + 1))" >"$INTENT"
}

# One script drives the panel and the cover at a time. A click while it runs only changes what is wanted: fast clicks
# used to start a script each, every one pressing fn+C and covering or uncovering the bar on its own.
if ! mkdir "$DRIVER" 2>/dev/null && kill -0 "$(cat "$DRIVER/pid" 2>/dev/null)" 2>/dev/null; then
  if press_closed_panel || [ "$(cut -d' ' -f1 "$INTENT" 2>/dev/null)" = open ]; then set_intent closed; else set_intent open; fi
  exit 0
fi
echo $$ >"$DRIVER/pid"
trap 'rm -f "$DRIVER/pid"; rmdir "$DRIVER" 2>/dev/null' EXIT

press_closed_panel && exit 0
if "$CTL" visible; then # opened some other way (fn+C): this click closes it
  "$CTL" open
  exit 0
fi

set_intent open
read -r _ handled <"$INTENT"
"$CONFIG_DIR/plugins/close_popups.sh" &
# The native bar stays up while the pointer is in the top strip, so the cover is kept until the pointer leaves it.
"$CONFIG_DIR/plugins/cover.sh" on

# Makes the panel match the intent with as few fn+C as possible, and never while Control Center is changing: a key that
# landed mid-animation, or among fast clicks, left an empty panel window on screen that no key or click would close.
# A key goes out once the clicks have stopped for QUIET_POLLS and the panel has looked the same for STEADY_POLLS, and gets
# KEY_WAIT_POLLS to take effect (MAX_KEYS per change). A panel the user closes elsewhere ends it. The first key waits only for
# the clicks (FIRST_WAIT): the panel starts closed and still. Sent at once, the clicks after it landed on a panel still
# opening (a click on the bar closes it) and left it empty.
# macOS opens the panel at the right edge of the screen: it is moved under this button as soon as its window exists.
center_panel() {
  local x
  x="$(sketchybar --query control | jq -r '.bounding_rects | to_entries[0].value | .origin[0] + .size[0] / 2' 2>/dev/null)"
  [ -n "$x" ] && [ "${x%%.*}" -ge 0 ] 2>/dev/null && "$CTL" center "$x" &
}

sleep "$FIRST_WAIT"
polls=0
away=0
since=-"$QUIET_POLLS"
changed_at=-"$STEADY_POLLS"
pressed_at=-"$KEY_WAIT_POLLS"
keys=0
seen=false
was=false
while [ "$polls" -lt "$MAX_POLLS" ]; do
  read -r intent serial <"$INTENT"
  visible=false
  "$CTL" visible && visible=true
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
  # Open and settled: the panel is the user's now. A click inside it can redraw its window, and a driver still watching
  # took the blink for a close elsewhere and shut the panel under the pointer. The cover waits for it on its own.
  $seen && [ $((polls - since)) -ge "$QUIET_POLLS" ] && [ $((polls - changed_at)) -ge "$STEADY_POLLS" ] && break
  wanted=false
  [ "$intent" = open ] && wanted=true
  if [ "$wanted" != "$visible" ]; then
    if [ "$intent" = open ] && { $seen || [ "$keys" -ge "$MAX_KEYS" ]; }; then
      set_intent closed # closed by a click elsewhere, or it does not open
      continue
    fi
    if [ $((polls - since)) -ge "$QUIET_POLLS" ] && [ $((polls - changed_at)) -ge "$STEADY_POLLS" ] &&
      [ $((polls - pressed_at)) -ge "$KEY_WAIT_POLLS" ] && [ "$keys" -lt "$MAX_KEYS" ]; then
      "$CTL" open
      [ "$intent" = open ] && center_panel
      pressed_at="$polls"
      keys=$((keys + 1))
    fi
  fi
  if [ "$intent" = closed ] && ! $visible && ! "$CTL" top; then
    away=$((away + 1))
    [ "$away" -ge "$GRACE_POLLS" ] && break
  else
    away=0
  fi
  sleep "$POLL"
  polls=$((polls + 1))
done
wait
# Let go first, then hand the cover to its waiter (it comes off once the panel is closed and the pointer has left the top).
rm -f "$DRIVER/pid"
rmdir "$DRIVER" 2>/dev/null
trap - EXIT
"$CONFIG_DIR/plugins/cover.sh" settle
