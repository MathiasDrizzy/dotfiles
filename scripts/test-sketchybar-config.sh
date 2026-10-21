#!/usr/bin/env bash
# shellcheck disable=SC2013,SC2016
# Test of mac/config/sketchybar (pure file checks, never touches the real SketchyBar or HOME).
#  S1 every script parses (bash -n) and the rc plus the plugins are executable
#  S2 every plugin the rc points to exists, and every icon or color a script uses is defined
#  S3 the bar is transparent (the glass is in the pills, so the notch gap stays clear) and sets notch_width
#  S4 AeroSpace starts SketchyBar and notifies it of workspace changes
#  S5 the installer installs the formulae and links every file
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SB="$ROOT/mac/config/sketchybar"
fails=0
check() { # name, command...
  local name="$1"
  shift
  if "$@"; then printf '  PASS  [S] %s\n' "$name"; else
    printf '  FAIL  [S] %s\n' "$name"
    fails=$((fails + 1))
  fi
}

syntax_ok() {
  local f
  for f in "$SB"/sketchybarrc "$SB"/colors.sh "$SB"/icons.sh "$SB"/plugins/*.sh; do bash -n "$f" || return 1; done
}
executable_ok() {
  local f
  for f in "$SB"/sketchybarrc "$SB"/plugins/*.sh; do [ -x "$f" ] || return 1; done
}
plugins_exist() {
  local p
  for p in $(grep -o '\$PLUGIN_DIR/[a-z_]*\.sh' "$SB/sketchybarrc" | sed 's#.*/##' | sort -u); do
    [ -f "$SB/plugins/$p" ] || return 1
  done
}
symbols_defined() {
  local v
  for v in $(grep -ho '\$[A-Z][A-Z_0-9]*' "$SB"/sketchybarrc "$SB"/plugins/*.sh | tr -d '$' | sort -u); do
    case "$v" in CONFIG_DIR | PLUGIN_DIR | FONT | HOME | NAME | INFO | FOCUSED_WORKSPACE | NF | SENDER | MAX_ENTRIES | SELF | WIDTH | HOLD | STEP | CACHE | LABEL_WIDTH | CHAR_PX_X10 | BASE_PAD_RIGHT | REREAD | ICON_SIZE | TEXT_SIZE | ARROW_SIZE | NERD_FONT | APPLE_SIZE | APPLE_FONT | APP_ICON_FONT | POLL | MAX_POLLS | SETTLE_POLLS | CTL | GRACE_POLLS | STATE | PRESS_PANEL | PRESS_MAX_SECONDS | DRAG_FLAG_MAX_SECONDS | DRAGGING | STRIP_HEIGHT | DRAG_THRESHOLD | GHOST | GHOST_HALF_WIDTH | SLOT_MARGIN | RELEASE_GRACE | GLIDE_FRAMES | TINT_FRAMES | DIM_ICON | DIM_BACKGROUND | TARGET_BACKGROUND | LEFT_COLUMN_LIMIT | ids | slot | lefts | rights | focused | source_slot | target_slot | down_x | mode | ghost_origin | PANEL_STATE | PANEL_BUSY | STALE_LOCK_SECONDS | SWAPPING | PARK | STASH | DROP | DROP_FRAMES | HOVER | COVER_CACHE | FADE_FRAMES | SLOT_WIDTH | HIDDEN_ICON | ANIMATION_CURVE | ANIMATION_FRAMES | ANIMATION_SECONDS | SLIDE_FRAMES | TEXT_FRAMES | SLIDE_SECONDS | TEXT_DELAY_SECONDS | WIDTHS | LOCK_RETRY_SECONDS | BACKDROP | BACKDROP_SCALE | COVER_HEIGHT | QUIET_POLLS | STEADY_POLLS | KEY_WAIT_POLLS | MAX_KEYS | INTENT | DRIVER | BUSY | BUTTONS | BUNDLE | COVER_BUSY | SETTLER | SETTLE_MAX | MENU_DELAY | REMEMBER_SECONDS | LOCK_TRIES | PRESS_MENU | COVER_GRACE | CLOSE_WAIT | MENU_DRIVER | FIRST_WAIT | PICK | EMPTIED_SECONDS | ASKED_SECONDS | binding_at | emptied | emptied_at | prev | line | DIRTY | RECONNECT_SECONDS | DISMISS_X | DISMISS_Y | closed_by_press | idle | handled | since | seen | pressed_at | intent | serial | visible | away | polls | changed_at | keys | was | wanted) continue ;; esac
    grep -q "^$v=" "$SB/colors.sh" "$SB/icons.sh" || {
      echo "undefined: $v" >&2
      return 1
    }
  done
}
no_event_var_shadowing() { # colors.sh and icons.sh are sourced by scripts that also read SketchyBar's event variables
  ! grep -qE '^(INFO|SENDER|NAME|BUTTON|MODIFIER|SCROLL_DELTA|FOCUSED_WORKSPACE)=' "$SB/colors.sh" "$SB/icons.sh"
}
one_icon_pack_and_sizes() { # every glyph is a sketchybar-app-font ligature, no duplicates, and font sizes come from ICON_SIZE / TEXT_SIZE
  python3 -I - "$SB/icons.sh" <<'PY' || return 1
import re, sys
names = set()
for line in open(sys.argv[1]):
    m = re.match(r"^([A-Z_0-9]+)=(?:'|\$')(.*)'", line)
    if not m or m.group(1) in ("APP_ICON_FONT", "APPLE_FONT", "APPLE", "NERD_FONT"):
        continue
    glyph = m.group(2)
    material = (m.group(1).startswith("BAT_") and m.group(1) != "BAT_CHARGING") or m.group(1) in ("RESTART", "VORSSAINT")
    if m.group(1) in names or not (re.fullmatch(r":[a-z_0-9]+:", glyph) or material):
        sys.exit(1)
    names.add(m.group(1))
PY
  ! grep -qE '(Bold|Regular):[0-9]' "$SB/sketchybarrc" "$SB"/plugins/*.sh
}
transparent_bar() {
  grep -q 'color=\$TRANSPARENT' "$SB/sketchybarrc" && grep -q 'notch_width=' "$SB/sketchybarrc"
}
aerospace_hooks() {
  local c="$ROOT/mac/config/aerospace/aerospace.toml"
  grep -q "exec-and-forget sketchybar'" "$c" && grep -q 'sketchybar --trigger aerospace_workspace_change' "$c"
}
no_topmost_toggle() {
  # Changing topmost recreates the bar window and blanks every pill for ~170 ms: it is set once, in the rc.
  ! grep -q 'topmost=' "$SB"/plugins/*.sh
}
workspaces_refresh_once() {
  # One driver item refreshes the whole row in one call; per-item refreshes showed two workspaces focused at once.
  [ "$(grep -c 'subscribe .space.*aerospace_workspace_change' "$SB/sketchybarrc")" -eq 1 ] &&
    grep -q 'animate' "$SB/plugins/aerospace.sh" &&
    ! grep -q 'icon.padding' "$SB/plugins/aerospace.sh" # a fixed icon.width ignores paddings, so the width is what animates
}
no_global_escape() {
  # A global Escape also reaches whatever app has the focus (it interrupted a running terminal session).
  ! grep -qi 'escape' "$ROOT/mac/tools/ctlcenter/ctlcenter.swift"
}
workspace_drag_swaps() {
  # Swapping parks the focus first, so no window is re-tiled in view; the drag itself is followed by drag.sh.
  grep -q 'move-node-to-workspace' "$SB/plugins/aerospace.sh" && grep -q 'aerospace workspace "$PARK"' "$SB/plugins/aerospace.sh" &&
    grep -q 'aerospace.sh \$sid click' "$SB/sketchybarrc" && grep -q 'aerospace.sh" "$source_id" swap' "$SB/plugins/drag.sh"
}
drag_is_followed() {
  # SketchyBar only reports where a drag ends, so the pointer is followed by ctlcenter, started once by the rc (a reload replaces it).
  grep -q 'ctlcenter" watch' "$SB/plugins/drag.sh" && grep -q 'add item drag_ghost' "$SB/sketchybarrc" &&
    grep -q 'PLUGIN_DIR/drag.sh' "$SB/sketchybarrc" && grep -q 'case "watch"' "$ROOT/mac/tools/ctlcenter/ctlcenter.swift" &&
    grep -q 'DRAGGING' "$SB/plugins/aerospace.sh"
}
panel_survives_fast_clicks() {
  # Plugins must not write colors while the right-hand panel is hidden or fading, and a click mid-animation is ignored.
  local f
  # They paint through panel_set, which holds the toggle's own lock for the call: checking first and painting later (control.sh
  # asks Bluetooth in between) let an icon land mid-slide and stay floating.
  for f in sys battery control; do
    grep -q '^ *panel_set ' "$SB/plugins/$f.sh" && ! grep -q '^ *sketchybar --set' "$SB/plugins/$f.sh" || return 1
  done
  grep -q '^panel_set() {' "$SB/colors.sh" && grep -q 'mkdir "$PANEL_BUSY"' "$SB/colors.sh" || return 1
  grep -q 'mkdir "$PANEL_BUSY"' "$SB/plugins/toggle.sh" && grep -q 'panel_busy" ] && exit 0' "$SB/plugins/hover.sh" || return 1
  # Releasing clears the exit trap: otherwise the trap deletes, at exit, the lock of the click that took over after the
  # early release (two toggles then run at once and leave the panel "open" with every item hidden). Only the stale-lock
  # cleanup and release_lock may remove it.
  grep -q '^  trap - EXIT$' "$SB/plugins/toggle.sh" && grep -q '^trap release_lock EXIT$' "$SB/plugins/toggle.sh" &&
    [ "$(grep -c 'rmdir "$PANEL_BUSY"' "$SB/plugins/toggle.sh")" -eq 2 ]
}
control_click_does_not_reopen() {
  # macOS closes the panel with the press of the button's own click; the script must know it was open at the press.
  # The press is checked before the window: at the release the closing panel is still fading on screen, and pressing fn+C
  # then opened it again. The watcher keeps sampling the panel while the pointer is near the top, so a press it notices a
  # poll late still knows the panel was open.
  local cc="$SB/plugins/controlcenter.sh" press visible
  press="$(grep -n 'PRESS_PANEL" 2>/dev/null)" = open' "$cc" | cut -d: -f1)"
  visible="$(grep -n '"$CTL" visible; then' "$cc" | cut -d: -f1)"
  [ -n "$press" ] && [ -n "$visible" ] && [ "$press" -lt "$visible" ] || return 1
  grep -q 'echo "$panel" >"$PRESS_PANEL"' "$SB/plugins/drag.sh" && grep -q 'wasOpen' "$ROOT/mac/tools/ctlcenter/ctlcenter.swift" || return 1
  # Fast clicks: one script drives the panel and the cover, the others only change what is wanted.
  grep -q 'mkdir "$DRIVER"' "$cc" && grep -q 'set_intent closed' "$cc" && grep -q 'set_intent open' "$cc" || return 1
  # fn+C only once the clicks stopped and the panel stood still: a key sent mid-animation left an empty panel on screen.
  grep -q 'polls - changed_at)) -ge "$STEADY_POLLS"' "$cc" && grep -q '"$keys" -lt "$MAX_KEYS"' "$cc" || return 1
  # ...and even the first one waits for the clicks to stop: sent at once, the clicks after it landed on a panel still
  # opening and left it empty. Only the wait for a still panel is skipped (it starts closed): that wait made it slow.
  # The wait is one sleep of FIRST_WAIT: counted in polls (each also asks for the panel) it took 0.45 s.
  ! grep -q '^"$CTL" open$' "$cc" && grep -q '^changed_at=-"$STEADY_POLLS"$' "$cc" &&
    grep -q '^since=-"$QUIET_POLLS"$' "$cc" && grep -q '^sleep "$FIRST_WAIT"' "$cc" && grep -q '^FIRST_WAIT=0.35 ' "$cc" || return 1
  # Once open and settled the panel is left alone (clicks inside redraw it; a driver still watching closed it) and the
  # cover waits for it on its own.
  driver_lets_go "$cc"
}
driver_lets_go() { # a panel or menu driver
  grep -q '^  \$seen && \[ \$((polls - since)) -ge "\$QUIET_POLLS" \] && \[ \$((polls - changed_at)) -ge "\$STEADY_POLLS" \] && break$' "$1" &&
    [ "$(tail -1 "$1")" = '"$CONFIG_DIR/plugins/cover.sh" settle' ]
}
status_items_animate() {
  # The right-hand items slide out of the date pill and back into it (their width animates) while their text fades, and a
  # hidden item stays transparent: SketchyBar keeps painting an item for a few frames after drawing=off while it animates,
  # so the visible colors given back on close left icons and numbers floating.
  local t="$SB/plugins/toggle.sh"
  grep -q -- '--animate' "$t" && grep -q 'width=0' "$t" && grep -q 'width=dynamic' "$t" && grep -q 'sys_pill' "$t" || return 1
  awk '/^collapse\(\) \{/,/^\}/' "$t" | grep -q 'drawing=off' && ! awk '/^collapse\(\) \{/,/^\}/' "$t" | grep -q 'MAUVE\|shown' || return 1
  # The slide ends where width=dynamic puts each item, measured right then (a width saved on the last close was stale once a
  # label changed) and with the gap to its right-hand neighbour: fixed widths drop the padding between items, and the items
  # jumped a few pixels at the end of the slide.
  ! grep -q 'WIDTHS' "$t" && grep -q 'slide_widths "${ITEMS\[@\]}"' "$t" && grep -A12 '^slide_widths() {' "$SB/colors.sh" | grep -q 'padding_right'
}
# Closing the last window of a workspace made AeroSpace follow macOS to an app on another workspace (AeroSpace #325):
# stay.sh brings the focus back, unless the switch was asked for (a key binding, a click on the bar, a drag swap).
# Runs stay.sh on recorded events with a fake aerospace; prints the workspaces it switched to.
stay_moves() { # windows left on the previous workspace, event lines...
  local tmp out
  tmp="$(mktemp -d)" || return 1
  mkdir -p "$tmp/bin" "$tmp/home/.cache/sketchybar"
  printf '%s\n' "${@:2}" >"$tmp/events"
  cat >"$tmp/bin/aerospace" <<STUB
#!/bin/bash
case "\$1" in
subscribe) cat "$tmp/events" ;;
list-windows) echo "$1" ;;
workspace) echo "\$2" >>"$tmp/moves" ;;
esac
STUB
  chmod +x "$tmp/bin/aerospace"
  [ "${STAY_PICK:-}" = 1 ] && touch "$tmp/home/.cache/sketchybar/workspace_pick"
  HOME="$tmp/home" PATH="$tmp/bin:$PATH" bash "$SB/plugins/stay.sh"
  out="$(cat "$tmp/moves" 2>/dev/null)"
  rm -rf "$tmp"
  echo "$out"
}
workspace_stays() {
  local emptied='{"_event":"focus-changed","workspace":"3"}' jump='{"_event":"focused-workspace-changed","prevWorkspace":"3","workspace":"2"}'
  local key='{"_event":"binding-triggered","binding":"alt-2","mode":"main"}'
  [ -x "$SB/plugins/stay.sh" ] && grep -q '"$PLUGIN_DIR/stay.sh"' "$SB/sketchybarrc" &&
    grep -q "pkill -f '^bash .\*/plugins/stay\\\\.sh\$'" "$SB/sketchybarrc" &&
    grep -q 'touch "$PICK"' "$SB/plugins/aerospace.sh" &&
    grep -q 'config/sketchybar/plugins/stay.sh|' "$ROOT/mac/scripts/check-links.sh" || return 1
  [ "$(stay_moves 0 "$emptied" "$jump")" = 3 ] || return 1            # the window closed: back to 3
  [ -z "$(stay_moves 0 "$emptied" "$key" "$jump")" ] || return 1      # alt-2: stays on 2
  [ -z "$(stay_moves 1 "$emptied" "$jump")" ] || return 1             # 3 still has a window
  [ -z "$(stay_moves 0 "$key" "$emptied" "$jump")" ] || return 1      # 3 was empty when alt-3 went there
  [ -z "$(STAY_PICK=1 stay_moves 0 "$emptied" "$jump")" ] || return 1 # a click on the bar picked 2
  [ -z "$(stay_moves 0 '{"_event":"focus-changed","workspace":"swap-park"}' \
    '{"_event":"focused-workspace-changed","prevWorkspace":"swap-park","workspace":"2"}')" ] # a drag swap
}
# The pill follows the player at once: media_watch.sh turns `media-control stream` into a now_playing_change event (the 2 s poll
# took up to 2.6 s to close it), and a change that lands while a slide runs is not lost but replayed after it.
media_follows_stream() {
  local w="$SB/plugins/media_watch.sh" rc="$SB/sketchybarrc"
  [ -x "$w" ] && grep -q 'media-control stream' "$w" && grep -q 'sketchybar --trigger now_playing_change' "$w" &&
    grep -q -- '--add event now_playing_change' "$rc" && grep -q -- '--subscribe media now_playing_change' "$rc" &&
    grep -q "pkill -f '^bash .\*/plugins/media_watch\\\\.sh\$'" "$rc" && grep -q '"$PLUGIN_DIR/media_watch.sh"' "$rc" &&
    ! grep -qw 'media_change' "$rc" && grep -q "pkill -f 'media-control/mediaremote-adapter" "$rc" &&
    grep -q 'touch "$DIRTY"' "$SB/plugins/media.sh" && grep -q 'config/sketchybar/plugins/media_watch.sh|' "$ROOT/mac/scripts/check-links.sh"
}
media_slides() {
  # The now playing pill slides open when a track loads and closed when the player quits, like the right-hand panel (it
  # used to pop in and out), and hidden items stay transparent.
  local m="$SB/plugins/media.sh"
  grep -q 'slide_widths "${ITEMS\[@\]}"' "$m" && grep -q -- '--animate' "$m" && grep -q 'width=0' "$m" && grep -q 'width=dynamic' "$m" || return 1
  awk '/^hide\(\) \{/,/^\}/' "$m" | grep -q 'drawing=off' && ! awk '/^hide\(\) \{/,/^\}/' "$m" | grep -q 'MAUVE' || return 1
  # Whether it is open is asked of SketchyBar itself: a state file went stale when a reload rebuilt the items mid-run.
  ! grep -q 'media-shown' "$m" && grep -q "sketchybar --query media | jq -r '.geometry.drawing'" "$m"
}
control_cover_is_wallpaper() {
  # A solid cover hid the wallpaper behind a black bar. The picture (the screen behind the bar, captured without it) lives in
  # the first bracket, so every pill paints over it; cover.sh is the one place that shows, hides and refreshes it.
  local rc="$SB/sketchybarrc" c="$SB/plugins/cover.sh" cover first
  cover="$(grep -n 'add bracket cover ' "$rc" | cut -d: -f1)"
  first="$(grep -n 'add bracket' "$rc" | grep -v 'add bracket cover ' | head -1 | cut -d: -f1)"
  [ -n "$cover" ] && [ -n "$first" ] && [ "$cover" -lt "$first" ] || return 1
  grep -q '"$CTL" backdrop' "$c" && grep -q -- '--set cover drawing=on' "$c" && grep -q 'case "backdrop"' "$ROOT/mac/tools/ctlcenter/ctlcenter.swift" &&
    ! grep -q -- '--set cover drawing=on' "$SB/plugins/controlcenter.sh" && grep -q 'cover.sh" on' "$SB/plugins/controlcenter.sh"
}
native_bar_stays_hidden() {
  # The system menu bar slid down over the bar whenever the pointer reached the top: the watcher reports the pointer
  # entering and leaving the top strip, and the cover is on while it is there. It only comes off once nothing needs it
  # (pointer away, no Control Center run, no panel or menu open).
  local c="$SB/plugins/cover.sh" d="$SB/plugins/drag.sh"
  grep -q 'print(atTop ? "top" : "away")' "$ROOT/mac/tools/ctlcenter/ctlcenter.swift" || return 1
  grep -q '^  top) .*cover.sh" on' "$d" && grep -q '^  away) .*cover.sh" off' "$d" || return 1
  awk '/^off\)/,/;;/' "$c" | grep -q 'covered && ! needed' && ! grep -q 'COVER_ON' "$c" || return 1
  local need
  need="$(awk '/^needed\(\) \{/,/^\}/' "$c")"
  grep -q '"$CTL" top' <<<"$need" && grep -q '"$CTL" visible' <<<"$need" && grep -q 'DRIVER/pid' <<<"$need" &&
    grep -q '"$CTL" shown "$MENU_EXTRA_BUNDLE"' <<<"$need" && grep -q '^MENU_EXTRA_BUNDLE="com.vorssaint.utils"' "$SB/colors.sh"
}
vorssaint_pill() {
  # Vorssaint lives in the hidden system menu bar: a pill next to Control Center opens its menu through Accessibility (the
  # native bar stays covered), and a click while the menu is open closes it instead of reopening it.
  local rc="$SB/sketchybarrc" v="$SB/plugins/vorssaint.sh"
  grep -q 'add item vorssaint right' "$rc" && grep -q 'vorssaint.sh' "$rc" && grep -q 'pill "$name"' "$rc" &&
    grep -q 'for name in .*vorssaint' "$rc" || return 1
  grep -q '"$CTL" menu "$BUNDLE"' "$v" && grep -q 'PRESS_MENU' "$v" && grep -q 'cover.sh" on' "$v" || return 1
  # Fast clicks: one script drives the menu, the others only flip what is wanted (the cover waits for it too).
  grep -q 'mkdir "$DRIVER"' "$v" && grep -q 'set_intent closed' "$v" && grep -q '"$keys" -lt "$MAX_KEYS"' "$v" &&
    awk '/^needed\(\) \{/,/^\}/' "$SB/plugins/cover.sh" | grep -q 'MENU_DRIVER/pid' || return 1
  # The first press waits for the clicks to stop too (see the Control Center button).
  ! grep -q '^  "$CTL" menu "$BUNDLE"' "$v" && grep -q '^changed_at=-"$STEADY_POLLS"$' "$v" &&
    grep -q '^since=-"$QUIET_POLLS"$' "$v" && grep -q '^sleep "$FIRST_WAIT"' "$v" && grep -q '^FIRST_WAIT=0.35 ' "$v" &&
    driver_lets_go "$v" || return 1
  # A menu closed by a press came back broken (the second click inside shut it): a click outside it, once it is gone,
  # finishes the close.
  grep -qF '[ "$intent" = closed ] && closed_by_press=true' "$v" &&
    grep -qF '$closed_by_press && [ "$intent" = closed ] && "$CTL" dismiss "$DISMISS_X" "$DISMISS_Y"' "$v" &&
    grep -qF 'set_intent open # it stayed open' "$v" && grep -q '^case "dismiss":' "$ROOT/mac/tools/ctlcenter/ctlcenter.swift" ||
    return 1
  grep -q 'echo "$menu" >"$PRESS_MENU"' "$SB/plugins/drag.sh" && grep -q 'watch "$STRIP_HEIGHT" "$MENU_EXTRA_BUNDLE"' "$SB/plugins/drag.sh" &&
    grep -q 'ITEMS=(sys sys_mem vorssaint control battery)' "$SB/plugins/toggle.sh"
}
installer_ok() {
  local f
  grep -q 'brew install felixkratz/formulae/sketchybar' "$ROOT/mac/install.sh" &&
    grep -q 'brew install ungive/media-control/media-control' "$ROOT/mac/install.sh" &&
    grep -q "ctlcenter.swift" "$ROOT/mac/install.sh" && [ -f "$ROOT/mac/tools/ctlcenter/ctlcenter.swift" ] || return 1
  # Every plugin is linked one by one: a new plugin missing here is simply not there after an install.
  for f in sketchybarrc colors.sh icons.sh "$SB"/plugins/*.sh; do
    grep -q "config/sketchybar/${f#"$SB"/}|" "$ROOT/mac/scripts/check-links.sh" || return 1
  done
}

check "all scripts parse" syntax_ok
check "the rc and the plugins are executable" executable_ok
check "every plugin the rc points to exists" plugins_exist
check "every icon and color used is defined" symbols_defined
check "colors.sh and icons.sh do not shadow SketchyBar event variables" no_event_var_shadowing
check "icons are one pack (sketchybar-app-font) and every font size comes from ICON_SIZE or TEXT_SIZE" one_icon_pack_and_sizes
check "the bar is transparent and keeps the notch gap" transparent_bar
check "AeroSpace starts SketchyBar and triggers workspace changes" aerospace_hooks
check "no plugin toggles the bar topmost flag (it blanks the pills)" no_topmost_toggle
check "AeroSpace workspaces refresh in one animated call from one driver item" workspaces_refresh_once
check "Control Center closes with fn+C, never a global Escape" no_global_escape
check "dragging a workspace onto another swaps their windows" workspace_drag_swaps
check "a drag is followed from the first pixel by a pointer watcher with a ghost pill" drag_is_followed
check "the right-hand panel survives fast clicks and plugin updates" panel_survives_fast_clicks
check "clicking the Control Center button while its panel is open closes it" control_click_does_not_reopen
check "the right-hand panel opens and closes with an animation" status_items_animate
check "the now playing pill slides open and closed" media_slides
check "the Control Center cover is a picture of the wallpaper, painted under every pill" control_cover_is_wallpaper
check "the system menu bar never shows over the bar" native_bar_stays_hidden
check "a Vorssaint pill next to Control Center opens its menu" vorssaint_pill
check "closing the last window of a workspace keeps the focus on it" workspace_stays
check "the now playing pill follows the player as it changes" media_follows_stream
check "install.sh installs the formulae and check-links.sh links the files" installer_ok

if [ "$fails" -eq 0 ]; then echo "test-sketchybar-config: PASS"; else
  echo "test-sketchybar-config: $fails FAIL"
  exit 1
fi
