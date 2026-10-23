#!/usr/bin/env bash
# Keeps the focus on a workspace whose last window just closed. macOS hands the focus to another app when a window closes,
# and AeroSpace follows that app to its own workspace (AeroSpace issue 325); the user meant to stay where they were. A
# switch the user asked for (a key binding, a click on the bar, a drag swap) is left alone. Runs for the whole session
# (started by the rc), on `aerospace subscribe`.

CACHE="$HOME/.cache/sketchybar"
PICK="$CACHE/workspace_pick" # aerospace.sh: a click on the bar picked a workspace
SWAPPING="$CACHE/swapping"
PARK=swap-park    # the workspace a drag swap parks the focus on (aerospace.sh)
EMPTIED_SECONDS=3 # macOS hands the focus over within this long after the last window closes
ASKED_SECONDS=1   # a switch this soon after a key binding or a click was asked for

binding_at=0
emptied=""
emptied_at=0
empty_seen=" " # workspaces whose last focus event had no window: a click on their bare desktop is not a window closing

# The user just asked for a switch.
asked() {
  local now
  now="$(date +%s)"
  [ $((now - binding_at)) -le "$ASKED_SECONDS" ] || [ -e "$SWAPPING" ] ||
    { [ -e "$PICK" ] && [ $((now - $(stat -f %m "$PICK"))) -le "$ASKED_SECONDS" ]; }
}

aerospace subscribe --no-send-initial binding-triggered focus-changed focused-workspace-changed |
  while read -r line; do
    case "$(jq -r '._event' <<<"$line")" in
    binding-triggered) binding_at="$(date +%s)" ;;
    focus-changed)
      # The focus is on a workspace with no window: its last one closed, unless the user just went there or it was already
      # empty (a click on the bare desktop, then on an app elsewhere, must not be taken back).
      ws="$(jq -r '.workspace' <<<"$line")"
      if [ -n "$(jq -r '.windowId // empty' <<<"$line")" ]; then
        empty_seen="${empty_seen/ $ws / }"
      else
        case "$empty_seen" in
        *" $ws "*) ;;
        *)
          if ! asked; then
            emptied="$ws"
            emptied_at="$(date +%s)"
          fi
          empty_seen="$empty_seen$ws "
          ;;
        esac
      fi
      ;;
    focused-workspace-changed)
      prev="$(jq -r '.prevWorkspace' <<<"$line")"
      if [ "$prev" = "$emptied" ] && [ "$prev" != "$PARK" ] && [ $(($(date +%s) - emptied_at)) -le "$EMPTIED_SECONDS" ] &&
        ! asked && [ "$(aerospace list-windows --workspace "$prev" --count)" = 0 ]; then
        emptied=""
        aerospace workspace "$prev"
      fi
      ;;
    esac
  done
