#!/usr/bin/env bash
# Menus of the active app in a popup, since the native menu bar is hidden. Click the app name for its menus, click a
# menu to list its items, click an item to run it. Uses System Events (needs the Accessibility permission).
#   appmenu.sh                 event handler (front_app_switched, mouse.*)
#   appmenu.sh menu <Name>     list the items of one menu
#   appmenu.sh run <Menu> <Item>
# shellcheck disable=SC1091,SC2154
source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/helpers.sh"
source "$CONFIG_DIR/icons.sh"
source "$CONFIG_DIR/icon_map.sh"

MAX_ENTRIES=30
SELF="$CONFIG_DIR/plugins/appmenu.sh"

quote() { printf "'%s'" "${1//\'/\'\\\'\'}"; }

close() {
  sketchybar --set front_pill popup.drawing=off background.color="$BAR_COLOR"
}

# The entries are built into one sketchybar call: the old ones go and the new ones come in the same step, so the popup never
# shows empty while System Events answers, nor grows one entry at a time.
entries=()
new_entries() {
  entries=()
  if [ "$(sketchybar --query front_pill | jq '[(.popup.items // [])[] | select(startswith("appmenu.entry."))] | length')" -gt 0 ]; then
    entries=(--remove '/appmenu\.entry\..*/')
  fi
}

add_entry() { # index, label, click command, icon
  entries+=(--add item "appmenu.entry.$1" popup.front_pill
    --set "appmenu.entry.$1" icon="${4:-}" icon.font="$NERD_FONT:Regular:$ICON_SIZE" icon.color="$BLUE" icon.width=26 icon.align=center
    label="$2" label.padding_right=14
    script="$CONFIG_DIR/plugins/hover.sh" click_script="$3"
    --subscribe "appmenu.entry.$1" mouse.entered mouse.exited)
}

top_menus() {
  bounded 5 osascript <<'AS'
tell application "System Events"
  tell (first process whose frontmost is true)
    set names to name of every menu bar item of menu bar 1
  end tell
end tell
set AppleScript's text item delimiters to linefeed
set out to {}
repeat with n in names
  if (n as text) is not "Apple" then set end of out to (n as text)
end repeat
return out as text
AS
}

menu_items() {
  bounded 5 osascript - "$1" <<'AS'
on run argv
  tell application "System Events"
    tell (first process whose frontmost is true)
      set names to name of every menu item of menu 1 of menu bar item (item 1 of argv) of menu bar 1
    end tell
  end tell
  set AppleScript's text item delimiters to linefeed
  set out to {}
  repeat with n in names
    if n is not missing value then set end of out to (n as text)
  end repeat
  return out as text
end run
AS
}

run_item() {
  bounded 5 osascript - "$1" "$2" <<'AS'
on run argv
  tell application "System Events"
    tell (first process whose frontmost is true)
      click menu item (item 2 of argv) of menu 1 of menu bar item (item 1 of argv) of menu bar 1
    end tell
  end tell
end run
AS
}

show_top() {
  local i=0 name names
  names="$(top_menus)"
  new_entries
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    add_entry "$i" "$name" "$SELF menu $(quote "$name")" "$CHEVRON_RIGHT"
    i=$((i + 1))
  done <<<"$names"
  sketchybar "${entries[@]}" --set apple popup.drawing=off background.color="$APPLE_BG" icon.color="$APPLE_ICON" \
    --set front_pill popup.drawing=on background.color="$BAR_PRESSED"
}

show_menu() {
  local i=0 name names
  names="$(menu_items "$1")"
  new_entries
  add_entry back "Menús" "$SELF top" "$CHEVRON_LEFT"
  while IFS= read -r name; do
    { [ -z "$name" ] || [ "$name" = "missing value" ]; } && continue
    [ "$i" -ge "$MAX_ENTRIES" ] && break
    add_entry "$i" "$name" "sketchybar --set front_pill popup.drawing=off; $SELF run $(quote "$1") $(quote "$name")"
    i=$((i + 1))
  done <<<"$names"
  sketchybar "${entries[@]}"
}

case "${1:-}" in
top)
  show_top
  exit 0
  ;;
menu)
  show_menu "$2"
  exit 0
  ;;
run)
  run_item "$2" "$3"
  exit 0
  ;;
esac

is_open="$(sketchybar --query front_pill | jq -r '.popup.drawing')"
case "$SENDER" in
front_app_switched)
  # The app in front now, not the one of this event: `ctlcenter stay` brings Finder forward for a few milliseconds, and when
  # that event's run ended last the pill kept showing Finder.
  front="$(bounded 2 lsappinfo info -only name "$(bounded 2 lsappinfo front)" 2>/dev/null | sed -n '1s/^"\(.*\)" ASN:.*/\1/p')"
  __icon_map "${front:-$INFO}"
  sketchybar --set front_app icon="$icon_result"
  "$CONFIG_DIR/plugins/app_name.sh" "${front:-$INFO}" &
  ;;
mouse.clicked)
  if [ "$is_open" = on ]; then close; else show_top; fi
  ;;
mouse.entered) [ "$is_open" = on ] || sketchybar --set front_pill background.color="$BAR_HOVER" ;;
mouse.exited) [ "$is_open" = on ] || sketchybar --set front_pill background.color="$BAR_COLOR" ;;
mouse.exited.global) close ;;
esac
