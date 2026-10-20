#!/usr/bin/env bash
# Menus of the active app in a popup, since the native menu bar is hidden. Click the app name for its menus, click a
# menu to list its items, click an item to run it. Uses System Events (needs the Accessibility permission).
#   appmenu.sh                 event handler (front_app_switched, mouse.*)
#   appmenu.sh menu <Name>     list the items of one menu
#   appmenu.sh run <Menu> <Item>
# shellcheck disable=SC1091
source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/icons.sh"

FONT="JetBrainsMono Nerd Font"
MAX_ENTRIES=30
SELF="$CONFIG_DIR/plugins/appmenu.sh"

quote() { printf "'%s'" "${1//\'/\'\\\'\'}"; }

close() {
  sketchybar --set front_app popup.drawing=off --set front_pill background.color="$BAR_COLOR"
}

clear_entries() { sketchybar --remove '/appmenu\.entry\..*/' >/dev/null 2>&1; }

add_entry() { # index, label, click command, icon
  sketchybar --add item "appmenu.entry.$1" popup.front_app \
    --set "appmenu.entry.$1" icon="${4:-}" icon.color="$MAUVE" icon.width=26 icon.align=center \
    label="$2" label.padding_right=14 label.font="$FONT:Regular:12.0" \
    script="$CONFIG_DIR/plugins/hover.sh" click_script="$3" \
    --subscribe "appmenu.entry.$1" mouse.entered mouse.exited
}

top_menus() {
  osascript <<'AS'
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
  osascript - "$1" <<'AS'
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
  osascript - "$1" "$2" <<'AS'
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
  clear_entries
  local i=0 name
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    add_entry "$i" "$name" "$SELF menu $(quote "$name")" "$CHEVRON_RIGHT"
    i=$((i + 1))
  done < <(top_menus)
  sketchybar --set apple popup.drawing=off background.color="$BAR_COLOR" icon.color="$TEXT" --set front_app popup.drawing=on --set front_pill background.color=0xf045475a
}

show_menu() {
  clear_entries
  add_entry back "Menús" "$SELF top" "$CHEVRON_LEFT"
  local i=0 name
  while IFS= read -r name; do
    { [ -z "$name" ] || [ "$name" = "missing value" ]; } && continue
    [ "$i" -ge "$MAX_ENTRIES" ] && break
    add_entry "$i" "$name" "sketchybar --set front_app popup.drawing=off; $SELF run $(quote "$1") $(quote "$name")"
    i=$((i + 1))
  done < <(menu_items "$1")
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

is_open="$(sketchybar --query front_app | jq -r '.popup.drawing')"
case "$SENDER" in
front_app_switched) sketchybar --set front_app background.image="app.$INFO" ;;
mouse.clicked)
  if [ "$is_open" = on ]; then close; else show_top; fi
  ;;
mouse.entered) [ "$is_open" = on ] || sketchybar --set front_pill background.color=0xf0313244 ;;
mouse.exited) [ "$is_open" = on ] || sketchybar --set front_pill background.color="$BAR_COLOR" ;;
mouse.exited.global) close ;;
esac
