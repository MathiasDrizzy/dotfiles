#!/usr/bin/env bash
# shellcheck disable=SC2013,SC2016
# Test of mac/config/sketchybar (pure file checks, never touches the real SketchyBar or HOME).
#  S1 every script parses (bash -n) and the rc plus the plugins are executable
#  S2 every plugin the rc points to exists, and every icon or color a script uses is defined
#  S3 the bar is transparent (every item sits in a solid box, so the notch gap stays clear) and sets notch_width
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
    case "$v" in CONFIG_DIR | PLUGIN_DIR | FONT | HOME | NAME | INFO | FOCUSED_WORKSPACE | SENDER | MAX_ENTRIES | SELF | HOLD | STEP | CACHE | ICON_SIZE | TEXT_SIZE | NERD_FONT | APPLE_SIZE | APPLE_FONT | APP_ICON_FONT | POLL | MAX_POLLS | SETTLE_POLLS | CTL | GRACE_POLLS | STATE | PRESS_PANEL | PRESS_MAX_SECONDS | DRAG_FLAG_MAX_SECONDS | DRAGGING | STRIP_HEIGHT | DRAG_THRESHOLD | GHOST | RELEASE_GRACE | GLIDE_FRAMES | TINT_FRAMES | DIM_ICON | DIM_BACKGROUND | TARGET_BACKGROUND | LEFT_COLUMN_LIMIT | ids | slot | focused | source_slot | target_slot | mode | SWAPPING | PARK | COVER_CACHE | FADE_FRAMES | SLOT_WIDTH | HIDDEN_ICON | AGAIN | LOCK | SLOTS | NATURAL | NAME_W | NAME_WIDTH | MEDIA_CHARS | CAP | MAIN_SCREEN | SLOT_STEP | SPARE_FOR_MORE | CHAR_WIDTH_TENTHS | MEDIA_OVERHEAD | MEDIA_MIN_CHARS | MEDIA_MAX_CHARS | ANIMATION_CURVE | ANIMATION_FRAMES | ANIMATION_SECONDS | SLIDE_FRAMES | TEXT_FRAMES | SLIDE_SECONDS | TEXT_DELAY_SECONDS | BACKDROP | BACKDROP_SCALE | COVER_HEIGHT | QUIET_POLLS | STEADY_POLLS | KEY_WAIT_POLLS | MAX_KEYS | INTENT | DRIVER | BUSY | BUTTONS | BUNDLE | COVER_BUSY | SETTLER | SETTLE_MAX | MENU_DELAY | REMEMBER_SECONDS | LOCK_TRIES | PRESS_MENU | COVER_GRACE | MENU_DRIVER | FIRST_WAIT | PICK | EMPTIED_SECONDS | ASKED_SECONDS | emptied | prev | line | DIRTY | RECONNECT_SECONDS | DISMISS_X | DISMISS_Y | idle | handled | seen | intent | serial | visible | away | polls | keys | was | wanted | SPREAD_ITEMS | MAX_LENGTH | LOCATE_SECONDS | USER_AGENT | KNOWN_NEW_MOON | SYNODIC_MONTH | OWNER | PAD_LEFT | PAD_RIGHT | FRAMES_PER_POINT | FRAME_RATE | HOLD_SECONDS | END_MARGIN | SHORTCUT | SHORTCUT_SECONDS | APPLE_OUT | MEDIA_BUNDLE | WALLPAPER_INDEX | WALLPAPER_SETTLE_SECONDS | BACKDROP_SECONDS) continue ;; esac
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
    # neutonfoo's Nerd Font glyphs (battery, Spotify, weather, moon, both menus) and the few the pack lacks
    material = m.group(1).startswith(("BAT_", "MOON_", "WEATHER", "SPOTIFY", "MEDIA_DOT")) or m.group(1) in ("RESTART", "MONITOR", "VORSSAINT", "TIME", "CALENDAR", "POWERLINE_ARROW", "CHEVRON_LEFT", "CHEVRON_RIGHT", "SETTINGS", "ICON_INFO", "SLEEP", "LOCK", "LOGOUT", "POWER")
    if m.group(1) in names or not (re.fullmatch(r":[a-z_0-9]+:", glyph) or material):
        sys.exit(1)
    names.add(m.group(1))
PY
  ! grep -qE '(Bold|Regular):[0-9]' "$SB/sketchybarrc" "$SB"/plugins/*.sh
}
# Switching the app menu (its menus <-> one menu's items) emptied the popup while System Events answered, then grew it one
# entry per call. Now the names are read first and every entry is replaced in a single sketchybar call.
app_menu_swaps_at_once() {
  local f="$SB/plugins/appmenu.sh"
  ! sed -n '/^add_entry() {/,/^}/p' "$f" | grep -q 'sketchybar' &&
    [ "$(sed -n '/^show_top() {/,/^}/p;/^show_menu() {/,/^}/p' "$f" | grep -c 'sketchybar "${entries\[@\]}"')" = 2 ] &&
    ! sed -n '/^show_top() {/,/^}/p;/^show_menu() {/,/^}/p' "$f" | grep -q 'clear_entries'
}
# Both menus use neutonfoo's icon font (JetBrainsMono Nerd Font) like the rest of the bar: the pack's pictures did not match.
menu_icons_are_nerd_font() {
  local name
  for name in ICON_INFO SETTINGS SLEEP LOCK LOGOUT RESTART POWER CHEVRON_LEFT CHEVRON_RIGHT; do
    grep -qE "^$name='[^:]" "$SB/icons.sh" || return 1
  done
  sed -n '/^apple_entry() {/,/^}/p' "$SB/sketchybarrc" | grep -q 'icon.font="$NERD_FONT:' &&
    sed -n '/^add_entry() {/,/^}/p' "$SB/plugins/appmenu.sh" | grep -q 'icon.font="$NERD_FONT:'
}
# The popup entries and the menu chevrons are pack ligatures that set no font of their own: with any other default font
# they printed as ":gear:" and ":chevron_right:".
default_icon_font_is_the_pack() {
  sed -n '/^sketchybar --default/,/^$/p' "$SB/sketchybarrc" | grep -q 'icon.font="$APP_ICON_FONT:'
}
# The boxes are solid, as in neutonfoo/dotfiles: every color is opaque (alpha ff) and from Catppuccin Macchiato (plus
# 242639, the box color his bar shows on screen), and the only see-through value is TRANSPARENT itself. A translucent hover,
# popup or outline read as a see-through bar.
MACCHIATO="242639 24273a 1e2030 181926 363a4f 494d64 5b6078 6e738d 8087a2 939ab7 a5adcb b8c0e0 cad3f5 c6a0f6 ed8796 ee99a0 \
f5a97f eed49f a6da95 8bd5ca 91d7e3 7dc4e4 8aadf4 b7bdf8 f5bde6 f0c6c6 f4dbd6"
solid_macchiato_colors() {
  local c
  for c in $(grep -rhoE '0x[0-9a-fA-F]{8}' "$SB"/colors.sh "$SB"/sketchybarrc "$SB"/plugins/*.sh | sort -u); do
    [ "$c" = 0x00000000 ] && continue
    case "$c" in 0xff*) ;; *)
      echo "translucent: $c" >&2
      return 1
      ;;
    esac
    grep -qw "${c#0xff}" <<<"$MACCHIATO" || {
      echo "not Macchiato: $c" >&2
      return 1
    }
  done
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
unplugged_pill_leaves_at_once() {
  # An unplugged monitor takes its pill with it: shrinking it first read as a flicker. The ext items that vanish with no
  # external monitor are hidden in the instant part of the call, before --animate.
  local a="$SB/plugins/aerospace.sh"
  grep -q 'gone+=(' "$a" && awk '/^sketchybar "\$\{gone/ {print; exit}' "$a" | grep -q 'gone\[@\]}.*--animate'
}
hover_exit_keeps_visible_tint() {
  # A workspace on screen without the focus (the other monitor's) wears SURFACE1; leaving it with the pointer must not blank it.
  awk '/^mouse\.exited\)/,/;;/' "$SB/plugins/aerospace.sh" | grep -q 'SURFACE1'
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
subscribe) while read -r line; do case "\$line" in sleep*) sleep "\${line#sleep }" ;; *) echo "\$line" ;; esac; done <"$tmp/events" ;;
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
# The strip is the top of the Mac's own screen: a monitor above it has negative y, which every "y < strip" test took for the
# strip, so the cover stayed on (a dark line under the bar) for as long as the pointer was on that monitor.
strip_is_the_macs_own() {
  local c="$ROOT/mac/tools/ctlcenter/ctlcenter.swift"
  grep -q '^func isInTopStrip(' "$c" && awk '/^func isInTopStrip\(/,/^}/' "$c" | grep -q 'CGDisplayBounds(CGMainDisplayID())' &&
    ! grep -qE 'location\.y < maxY|pointerLocation\(\)\.y <' "$c"
}
workspace_stays() {
  local emptied='{"_event":"focus-changed","workspace":"3"}' jump='{"_event":"focused-workspace-changed","prevWorkspace":"3","workspace":"2"}'
  local key='{"_event":"binding-triggered","binding":"alt-2","mode":"main"}'
  [ -x "$SB/plugins/stay.sh" ] && grep -q '"$PLUGIN_DIR/stay.sh"' "$SB/sketchybarrc" &&
    grep -q "pkill -f '^bash .\*/plugins/stay\\\\.sh\$'" "$SB/sketchybarrc" &&
    grep -q 'touch "$PICK"' "$SB/plugins/aerospace.sh" &&
    grep -q 'config/sketchybar/plugins/stay.sh|' "$ROOT/mac/scripts/check-links.sh" || return 1
  # Going back flickered through the other workspace: `ctlcenter stay` keeps Finder right behind an app alone on screen in
  # macOS's order of apps, so its quit hands the focus to Finder, with no window for AeroSpace to follow.
  local c="$ROOT/mac/tools/ctlcenter/ctlcenter.swift"
  grep -q '^case "stay":' "$c" && grep -q 'func putFinderBehind(' "$c" && grep -q 'finder.activate(options: \[\])' "$c" &&
    grep -q '^let aloneCheckDelays = ' "$c" &&
    grep -q "pkill -f '^\[^ \]\*/ctlcenter stay\$'" "$SB/sketchybarrc" && grep -q 'nohup "$HOME/.local/bin/ctlcenter" stay ' "$SB/sketchybarrc" || return 1
  [ "$(stay_moves 0 "$emptied" "$jump")" = 3 ] || return 1            # the window closed: back to 3
  [ -z "$(stay_moves 0 "$emptied" "$key" "$jump")" ] || return 1      # alt-2: stays on 2
  [ -z "$(stay_moves 1 "$emptied" "$jump")" ] || return 1             # 3 still has a window
  [ -z "$(stay_moves 0 "$key" "$emptied" "$jump")" ] || return 1      # 3 was empty when alt-3 went there
  [ -z "$(STAY_PICK=1 stay_moves 0 "$emptied" "$jump")" ] || return 1 # a click on the bar picked 2
  # A click on the empty desktop of a workspace that was already empty is not a window closing: clicking an app on the other
  # monitor right after used to bring the focus back to the empty workspace.
  local win='{"_event":"focus-changed","workspace":"3","windowId":7}'
  [ "$(stay_moves 0 "$win" "$emptied" "$jump")" = 3 ] || return 1
  [ -z "$(stay_moves 0 "$key" "$emptied" "sleep 1.2" "$emptied" "$jump")" ] || return 1
  [ -z "$(stay_moves 0 '{"_event":"focus-changed","workspace":"swap-park"}' \
    '{"_event":"focused-workspace-changed","prevWorkspace":"swap-park","workspace":"2"}')" ] # a drag swap
}
# The pill follows the player at once: media_watch.sh turns `media-control stream` into a now_playing_change event (the 2 s poll
# took up to 2.6 s to close it), and a change that lands while a slide runs is not lost but replayed after it.
# The pill is Spotify's alone: a video playing in a browser tab reports itself as now playing too, and showed up as a track.
media_is_spotify_only() {
  local m="$SB/plugins/media.sh"
  grep -q '^MEDIA_BUNDLE="com.spotify.client"' "$m" && grep -q 'bundleIdentifier' "$m" && grep -q '"$MEDIA_BUNDLE"' "$m"
}

# The cover's picture of the desktop is taken again when the wallpaper changes (macOS rewrites its Index.plist), also with
# nothing touching the cover: it used to be refreshed only after a use, at most once a minute, and kept the old desktop.
cover_follows_wallpaper() {
  local c="$SB/plugins/cover.sh"
  grep -q '^WALLPAPER_INDEX=.*com.apple.wallpaper/Store/Index.plist' "$c" && grep -q '^wallpaper_changed()' "$c" &&
    grep -q '^refresh)' "$c" && grep -q 'cover.sh refresh' "$SB/sketchybarrc" && grep -q 'update_freq=' <(grep 'cover.sh refresh' -B3 "$SB/sketchybarrc")
}

media_follows_stream() {
  local w="$SB/plugins/media_watch.sh" rc="$SB/sketchybarrc"
  [ -x "$w" ] && grep -q 'media-control stream' "$w" && grep -q 'sketchybar --trigger now_playing_change' "$w" &&
    grep -q -- '--add event now_playing_change' "$rc" && grep -q -- '--subscribe media now_playing_change' "$rc" &&
    grep -q "pkill -f '^bash .\*/plugins/media_watch\\\\.sh\$'" "$rc" && grep -q '"$PLUGIN_DIR/media_watch.sh"' "$rc" &&
    ! grep -qw 'media_change' "$rc" && grep -q "pkill -f 'media-control/mediaremote-adapter" "$rc" &&
    grep -q 'touch "$DIRTY"' "$SB/plugins/media.sh" && grep -q 'config/sketchybar/plugins/media_watch.sh|' "$ROOT/mac/scripts/check-links.sh"
}
media_slides() {
  # The now playing pill slides open when a track loads and closed when the player quits (it used to pop in and out), and
  # hidden items stay transparent.
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
  # Closing is a click outside the menu, never a press nor Escape: a menu closed either way left Vorssaint so that the next
  # one shut at a click inside it (every other opening). The pointer comes back with a posted move, not a warp: after a warp
  # macOS ignores the mouse for a moment, and the pointer looked stuck on the left.
  local dismiss
  dismiss="$(awk '/^func dismiss\(/,/^}/' "$ROOT/mac/tools/ctlcenter/ctlcenter.swift")"
  [ "$(grep -c '"$CTL" menu "$BUNDLE"' "$v")" = 1 ] && grep -qF '"$CTL" dismiss "$DISMISS_X" "$DISMISS_Y"' "$v" &&
    grep -qF 'set_intent open # it stayed open' "$v" && grep -q 'usleep(dismissHoldMicroseconds)' <<<"$dismiss" &&
    grep -q '^case "dismiss":' "$ROOT/mac/tools/ctlcenter/ctlcenter.swift" && grep -q 'mouseMoved' <<<"$dismiss" &&
    ! grep -q 'CGWarpMouseCursorPosition' <<<"$dismiss" || return 1
  grep -q 'echo "$menu" >"$PRESS_MENU"' "$SB/plugins/drag.sh" && grep -q 'watch "$STRIP_HEIGHT" "$MENU_EXTRA_BUNDLE"' "$SB/plugins/drag.sh" &&
    ! grep -q -- '--set vorssaint drawing=off' "$SB/sketchybarrc"
}
# macOS opens the Control Center panel at the right edge of the screen and it cannot be moved before it shows, so the
# button lives there: the rightmost item, always drawn, one fixed width and with no label (a Bluetooth
# name widened it). Nothing moves the panel (scripts/test-sketchybar-anchor.sh checks the item live).
# The bar is minimal: the status items stay on it, with no chevron folding them away, no drawer animation and no lock that
# plugins had to take to paint them.
status_items_always_shown() {
  local rc="$SB/sketchybarrc"
  [ ! -e "$SB/plugins/toggle.sh" ] && ! grep -q -- '--add item chevron' "$rc" &&
    ! grep -qE -- '--set (sys|sys_mem|sys_pill|vorssaint) drawing=off' "$rc" &&
    ! grep -rqE 'PANEL_STATE|PANEL_BUSY|panel_set|panel_busy' "$SB" && ! grep -q 'plugins/toggle.sh' "$ROOT/mac/scripts/check-links.sh" && ! grep -q 'plugins/toggle.sh' "$ROOT/mac/install.sh"
}
control_anchored() {
  local rc="$SB/sketchybarrc" c="$SB/plugins/control.sh"
  [ "$(grep -o -- '--add item [a-z_]* right' "$rc" | sed -n 2p)" = '--add item control right' ] &&
    grep -qE -- 'icon.width=[0-9]+ ' <<<"$(grep -A2 -- '--set control ' "$rc")" && ! grep -q -- '--set control width=' "$rc" && ! grep -q -- '--set control drawing=off' "$rc" &&
    ! grep -q 'label' "$c" && ! grep -q 'panel_' "$c" &&
    ! grep -q '"$CTL" center' "$SB/plugins/controlcenter.sh" && ! grep -q 'case "center":' "$ROOT/mac/tools/ctlcenter/ctlcenter.swift" &&
    [ -x "$ROOT/scripts/test-sketchybar-anchor.sh" ]
}
# The cover changed the bar's height, margin and offset: SketchyBar resized its window and the pills shook for half a second.
# The bar keeps one geometry; the cover only shows or hides.
cover_keeps_bar_still() {
  ! grep -q -- '--bar' "$SB/plugins/cover.sh" && grep -q 'height=40 margin=0 y_offset=0' "$SB/sketchybarrc"
}
# ctlcenter stay puts Finder in front for a few milliseconds; the front app pill showed Finder when its event ran last.
front_app_is_the_real_one() {
  grep -q 'lsappinfo front' "$SB/plugins/appmenu.sh"
}
front_app_name_is_fixed() { # a name never resizes the pill: it has a fixed width and a longer one slides there and back
  local rc="$SB/sketchybarrc" scroll="$SB/plugins/app_name.sh"
  grep -q 'front_app.name .*label.width="\$APP_NAME_WIDTH"' "$rc" &&
    grep -q 'app_name.sh' "$SB/plugins/appmenu.sh" && ! grep -q 'front_app.name label=' "$SB/plugins/appmenu.sh" &&
    grep -q -- '--animate' "$scroll" && [ "$(grep -c 'label.padding_left=' "$scroll")" -ge 2 ]
}
# The temperature is Apple Weather's (what the Mac and the iPhone show) through a Shortcuts shortcut, when it exists;
# Open-Meteo, a different source that read a degree off, is only the fallback. The shortcut writes nothing into TMPDIR
# (mktemp): its output goes to the bar's cache.
# The app menu hangs from the whole pill, centered under it: hung from the icon block it opened off to the left.
app_menu_centered() {
  grep -qF '(.popup.items // [])' "$SB/plugins/appmenu.sh" || return 1 # a pill without entries yet has no items list
  sed -n '/--add bracket front_pill/,/^pill front_pill/p' "$SB/sketchybarrc" | grep -q 'popup.align=center' && ! grep -q 'popup.front_app\b' "$SB/plugins/appmenu.sh" &&
    ! grep -rq 'front_app popup.drawing\|--query front_app |' "$SB/plugins" "$SB/sketchybarrc" &&
    ! sed -n '/--add item front_app left/,/--add item front_app.arrow/p' "$SB/sketchybarrc" | grep -q 'popup\.'
}
weather_is_apples() {
  local w="$SB/plugins/weather.sh"
  grep -q '^SHORTCUT="Temperatura barra"' "$w" && grep -q 'shortcuts run "$SHORTCUT" --output-path "$APPLE_OUT"' "$w" &&
    grep -q '^APPLE_OUT="$CACHE/' "$w" && ! grep -q 'mktemp' "$w" && grep -q 'open-meteo' "$w" &&
    [ "$(grep -n 'shortcuts run' "$w" | head -1 | cut -d: -f1)" -lt "$(grep -n 'open-meteo' "$w" | head -1 | cut -d: -f1)" ]
}
battery_always_shown() {
  local rc="$SB/sketchybarrc" b="$SB/plugins/battery.sh"
  ! grep -q -- '--set battery drawing=off' "$rc" && grep -q '^sketchybar --set "$NAME"' "$b"
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
check "icons default to the app font, so popup ligatures (:gear:) draw as glyphs" default_icon_font_is_the_pack
check "both menus draw Nerd Font icons, like the rest of the bar" menu_icons_are_nerd_font
check "the app menu swaps its entries in one step, never empty or growing" app_menu_swaps_at_once
check "the bar is transparent and keeps the notch gap" transparent_bar
check "every color is solid Catppuccin Macchiato (no translucent box, popup or hover)" solid_macchiato_colors
check "AeroSpace starts SketchyBar and triggers workspace changes" aerospace_hooks
check "no plugin toggles the bar topmost flag (it blanks the pills)" no_topmost_toggle
check "AeroSpace workspaces refresh in one animated call from one driver item" workspaces_refresh_once
check "Control Center closes with fn+C, never a global Escape" no_global_escape
check "dragging a workspace onto another swaps their windows" workspace_drag_swaps
check "a drag is followed from the first pixel by a pointer watcher with a ghost pill" drag_is_followed
check "clicking the Control Center button while its panel is open closes it" control_click_does_not_reopen
check "the status items are always on the bar: no chevron, no drawer" status_items_always_shown
check "the now playing pill slides open and closed" media_slides
check "the Control Center cover is a picture of the wallpaper, painted under every pill" control_cover_is_wallpaper
check "the system menu bar never shows over the bar" native_bar_stays_hidden
check "a Vorssaint pill next to Control Center opens its menu" vorssaint_pill
check "an unplugged monitor's pill leaves at once, not shrinking" unplugged_pill_leaves_at_once
check "leaving a visible workspace with the pointer keeps its tint" hover_exit_keeps_visible_tint
check "closing the last window of a workspace keeps the focus on it" workspace_stays
check "the cover follows the pointer only on the Mac's own screen (a monitor above has negative y)" strip_is_the_macs_own
check "the now playing pill follows the player as it changes" media_follows_stream
check "the now playing pill is Spotify's alone" media_is_spotify_only
check "the cover picture follows a wallpaper change" cover_follows_wallpaper
check "the battery pill is always on the bar" battery_always_shown
check "the Control Center button is anchored at the right edge, so its panel opens under it" control_anchored
check "the cover never changes the bar's geometry" cover_keeps_bar_still
check "the front app pill shows the app really in front" front_app_is_the_real_one
check "the app menu opens centered under the front app pill" app_menu_centered
check "the temperature comes from Apple Weather (a Shortcuts shortcut), Open-Meteo only as the fallback" weather_is_apples
check "the front app name keeps a fixed width and slides a long name there and back" front_app_name_is_fixed
check "install.sh installs the formulae and check-links.sh links the files" installer_ok

if [ "$fails" -eq 0 ]; then echo "test-sketchybar-config: PASS"; else
  echo "test-sketchybar-config: $fails FAIL"
  exit 1
fi
