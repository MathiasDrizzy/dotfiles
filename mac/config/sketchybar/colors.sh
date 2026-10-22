# shellcheck shell=bash disable=SC2034
# Catppuccin Macchiato, the palette of neutonfoo/dotfiles's bar (0xAARRGGBB). Every color is solid: the only see-through
# value is TRANSPARENT, for the bar itself and the items that sit inside a box.
BASE=0xff24273a
CRUST=0xff181926
SURFACE0=0xff363a4f
SURFACE1=0xff494d64
OVERLAY0=0xff6e738d
TEXT=0xffcad3f5
MAUVE=0xffc6a0f6
RED=0xffed8796
MAROON=0xffee99a0
GREEN=0xffa6da95
YELLOW=0xffeed49f
BLUE=0xff8aadf4
PEACH=0xfff5a97f
TEAL=0xff8bd5ca
PINK=0xfff5bde6
SAPPHIRE=0xff7dc4e4
TRANSPARENT=0x00000000

# The bar is neutonfoo/dotfiles's: every item is its own small solid box, 5 points apart, with a colored icon; the Apple
# menu, the focused workspace and the front app are solid color blocks with a dark icon.
BAR_COLOR=0xff242639  # a box at rest: solid, the color his boxes show on screen
BAR_BORDER=$SURFACE1  # the popups' outline
BAR_HOVER=$SURFACE0   # under the pointer
BAR_PRESSED=$SURFACE1 # a box whose popup is open, or a click
PILL_HEIGHT=26
PILL_RADIUS=5
PILL_GAP=5
# The camera housing of the built-in display is 208 points wide (NSScreen auxiliaryTopLeftArea/RightArea on a 15" M2
# MacBook Air): the bar keeps 8 more on each side free, so no box ever sits under it.
NOTCH_WIDTH=224
SPACE_BLOCK=$MAUVE   # the focused workspace
APP_BLOCK=$GREEN     # the front app's block and its arrow
MOON_BLOCK=$SAPPHIRE # his moon box, solid
APPLE_BG=$PEACH      # the Apple block: at rest, under the pointer, with its popup open
APPLE_ICON=$BASE
APPLE_HOVER=$YELLOW
APPLE_PRESSED=$RED
# The labels right of Vorssaint keep these widths at least; vorssaint.sh widens them to line it up with its native extra.
BATTERY_LABEL_WIDTH=30
DATE_LABEL_WIDTH=72
TIME_LABEL_WIDTH=36
APP_NAME_WIDTH=94 # "Google Chrome" fits; a longer name slides inside this width (app_name.sh)

# The menu bar extra with a pill of its own next to Control Center (vorssaint.sh); the watcher and the cover follow its menu.
MENU_EXTRA_BUNDLE="com.vorssaint.utils"
# Where width=dynamic puts each item, as fixed widths ("item width" lines): its drawn size plus the gap to its right-hand
# neighbour (fixed widths drop the padding between items; the last one keeps its own). Measured right before each slide,
# while the items are drawn: a width saved on the last close was stale once a label had changed, and the items jumped a
# few pixels when the slide ended.
slide_widths() { # items, left to right
  local items=("$@") i item next query width
  for i in "${!items[@]}"; do
    item="${items[$i]}"
    next="${items[$((i + 1))]}"
    query="$(sketchybar --query "$item")"
    width="$(jq -r '.bounding_rects | to_entries[0].value.size[0] | floor' <<<"$query")"
    if [ -n "$next" ]; then
      width=$((width + $(jq -r '.geometry.padding_right' <<<"$query") + $(sketchybar --query "$next" | jq -r '.geometry.padding_left')))
    fi
    echo "$item $width"
  done
}
width_of() { awk -v i="$1" '$1 == i {print $2}' <<<"$2"; }
