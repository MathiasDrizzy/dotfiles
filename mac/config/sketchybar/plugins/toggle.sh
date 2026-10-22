#!/usr/bin/env bash
# shellcheck disable=SC1091
# Expands or collapses the status items; the chevron points toward where they will go.
# The items slide out of the date pill and back into it like a drawer: their width animates while their text fades, so the
# labels never show piled up. A hidden item stays transparent: SketchyBar keeps painting an animating item for a few frames
# after drawing=off, and the visible colors given back at that moment left icons and numbers floating.
# Clicks that arrive while it animates are ignored, and the colors it fades to are fixed (never read back from an item that
# is mid-fade).
source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/icons.sh"

ITEMS=(sys sys_mem vorssaint) # the content; the pills right of it stay on the bar
PILLS=(sys_pill vorssaint)    # what has the glass background (the bracket is shown and hidden with its items)
ANIMATION_CURVE=sin
SLIDE_FRAMES=24
TEXT_FRAMES=9
SLIDE_SECONDS=0.45
TEXT_DELAY_SECONDS=0.22 # the text fades in once the drawer is half open
STALE_LOCK_SECONDS=3
LOCK_RETRY_SECONDS=0.02

# One toggle at a time. mkdir is atomic, so two clicks can never both get in (a lock older than STALE_LOCK_SECONDS is a
# crashed run, not a busy one; a lock that vanishes while it is being read was just released, so that click is dropped).
acquire_lock() {
  local locked_at
  # A plugin painting the panel holds the lock for one call: wait those few milliseconds instead of dropping the click.
  for _ in 1 2 3 4 5; do
    mkdir "$PANEL_BUSY" 2>/dev/null && return 0
    sleep "$LOCK_RETRY_SECONDS"
  done
  locked_at="$(stat -f %m "$PANEL_BUSY" 2>/dev/null)" || return 1
  [ $(($(date +%s) - locked_at)) -ge "$STALE_LOCK_SECONDS" ] || return 1
  rmdir "$PANEL_BUSY" 2>/dev/null
  mkdir "$PANEL_BUSY" 2>/dev/null
}
mkdir -p "$(dirname "$PANEL_STATE")"
acquire_lock || exit 0
# The one place the lock is released; it also clears the exit trap, so a run that already let go can never delete the lock of
# the click that took over after it.
release_lock() {
  trap - EXIT
  rmdir "$PANEL_BUSY" 2>/dev/null
}
trap release_lock EXIT

collapse() {
  local item widths args=() fade_out=() slide=()
  widths="$(slide_widths "${ITEMS[@]}")"
  for item in "${ITEMS[@]}"; do
    args+=(--set "$item" width="$(width_of "$item" "$widths")")
    fade_out+=(--set "$item" icon.color="$TRANSPARENT" label.color="$TRANSPARENT")
    slide+=(--set "$item" width=0)
  done
  for item in "${PILLS[@]}"; do
    slide+=(--set "$item" background.color="$TRANSPARENT" background.border_color="$TRANSPARENT")
  done
  # The fixed widths first (no visible change), then the text fades quickly while the drawer closes.
  sketchybar "${args[@]}" --animate "$ANIMATION_CURVE" "$TEXT_FRAMES" "${fade_out[@]}" \
    --animate "$ANIMATION_CURVE" "$SLIDE_FRAMES" "${slide[@]}" --set chevron icon="$CHEVRON_LEFT"
  sleep "$SLIDE_SECONDS"
  args=()
  for item in "${ITEMS[@]}" sys_pill; do args+=(--set "$item" drawing=off); done
  for item in "${ITEMS[@]}"; do args+=(--set "$item" width=dynamic); done
  sketchybar "${args[@]}"
  echo off >"$PANEL_STATE"
}

expand() {
  local item widths args=() slide=() fade_in=() dynamic=()
  for item in "${ITEMS[@]}"; do
    args+=(--set "$item" drawing=on width=0 icon.color="$TRANSPARENT" label.color="$TRANSPARENT")
    fade_in+=(--set "$item" icon.color="$MAUVE" label.color="$TEXT")
    dynamic+=(--set "$item" width=dynamic)
  done
  args+=(--set sys_pill drawing=on)
  for item in "${PILLS[@]}"; do
    args+=(--set "$item" background.color="$TRANSPARENT" background.border_color="$TRANSPARENT")
    slide+=(--set "$item" background.color="$BAR_COLOR" background.border_color="$BAR_BORDER")
  done
  sketchybar "${args[@]}"
  widths="$(slide_widths "${ITEMS[@]}")" # a drawn item reports the size of its content even at width 0
  for item in "${ITEMS[@]}"; do slide+=(--set "$item" width="$(width_of "$item" "$widths")"); done
  sketchybar --animate "$ANIMATION_CURVE" "$SLIDE_FRAMES" "${slide[@]}" --set chevron icon="$CHEVRON_RIGHT"
  sleep "$TEXT_DELAY_SECONDS"
  sketchybar --animate "$ANIMATION_CURVE" "$TEXT_FRAMES" "${fade_in[@]}"
  sleep "$TEXT_DELAY_SECONDS"
  # Back to measuring themselves, so a longer label (a Bluetooth device name) gets its room.
  sketchybar "${dynamic[@]}"
  echo on >"$PANEL_STATE"
  release_lock
  sketchybar --update # the plugins skipped their updates while the panel was hidden
}

if [ "$(cat "$PANEL_STATE" 2>/dev/null)" = on ]; then collapse; else expand; fi
