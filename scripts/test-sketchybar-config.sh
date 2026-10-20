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
    case "$v" in CONFIG_DIR | PLUGIN_DIR | FONT | HOME | NAME | INFO | FOCUSED_WORKSPACE | NF | SENDER | MAX_ENTRIES | SELF | WIDTH | HOLD | STEP | CACHE | LABEL_WIDTH | CHAR_PX_X10 | BASE_PAD_RIGHT | REREAD | ICON_SIZE | TEXT_SIZE | ARROW_SIZE | NERD_FONT | APPLE_SIZE | APPLE_FONT | APP_ICON_FONT | POLL | MAX_POLLS | SETTLE_POLLS | CTL | GRACE_POLLS | STATE | PRESS_PANEL | PRESS_MAX_SECONDS | DRAG_FLAG_MAX_SECONDS | DRAGGING | STRIP_HEIGHT | DRAG_THRESHOLD | GHOST | GHOST_HALF_WIDTH | SLOT_MARGIN | RELEASE_GRACE | GLIDE_FRAMES | TINT_FRAMES | DIM_ICON | DIM_BACKGROUND | TARGET_BACKGROUND | LEFT_COLUMN_LIMIT | ids | slot | lefts | rights | focused | source_slot | target_slot | down_x | mode | ghost_origin | PANEL_STATE | PANEL_BUSY | STALE_LOCK_SECONDS | SWAPPING | PARK | STASH | DROP | DROP_FRAMES | HOVER | COVER_CACHE | FADE_FRAMES | SLOT_WIDTH | HIDDEN_ICON | ANIMATION_CURVE | ANIMATION_FRAMES | ANIMATION_SECONDS | SLIDE_FRAMES | TEXT_FRAMES | SLIDE_SECONDS | TEXT_DELAY_SECONDS | WIDTHS) continue ;; esac
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
    material = (m.group(1).startswith("BAT_") and m.group(1) != "BAT_CHARGING") or m.group(1) == "RESTART"
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
  for f in sys battery control; do grep -q '^panel_idle || exit 0$' "$SB/plugins/$f.sh" || return 1; done
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
  grep -q 'echo "$panel" >"$PRESS_PANEL"' "$SB/plugins/drag.sh" && grep -q 'panelWasOpen' "$ROOT/mac/tools/ctlcenter/ctlcenter.swift"
}
status_items_animate() {
  # The right-hand items slide out of the date pill and back into it (their width animates) while their text fades, and a
  # hidden item stays transparent: SketchyBar keeps painting an item for a few frames after drawing=off while it animates,
  # so the visible colors given back on close left icons and numbers floating.
  local t="$SB/plugins/toggle.sh"
  grep -q -- '--animate' "$t" && grep -q 'width=0' "$t" && grep -q 'width=dynamic' "$t" && grep -q 'sys_pill' "$t" || return 1
  awk '/^collapse\(\) \{/,/^\}/' "$t" | grep -q 'drawing=off' && ! awk '/^collapse\(\) \{/,/^\}/' "$t" | grep -q 'MAUVE\|shown'
}
installer_ok() {
  local f
  grep -q 'brew install felixkratz/formulae/sketchybar' "$ROOT/mac/install.sh" &&
    grep -q 'brew install ungive/media-control/media-control' "$ROOT/mac/install.sh" &&
    grep -q "ctlcenter.swift" "$ROOT/mac/install.sh" && [ -f "$ROOT/mac/tools/ctlcenter/ctlcenter.swift" ] || return 1
  for f in sketchybarrc colors.sh icons.sh plugins/aerospace.sh plugins/media.sh plugins/toggle.sh; do
    grep -q "config/sketchybar/$f|" "$ROOT/mac/scripts/check-links.sh" || return 1
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
check "install.sh installs the formulae and check-links.sh links the files" installer_ok

if [ "$fails" -eq 0 ]; then echo "test-sketchybar-config: PASS"; else
  echo "test-sketchybar-config: $fails FAIL"
  exit 1
fi
