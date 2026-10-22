# shellcheck shell=bash disable=SC2034
# Catppuccin Mocha, the same palette as the Ghostty theme (0xAARRGGBB).
BASE=0xff1e1e2e
MANTLE=0xff181825
SURFACE0=0xff313244
SURFACE1=0xff45475a
OVERLAY0=0xff6c7086
TEXT=0xffcdd6f4
SUBTEXT=0xffa6adc8
MAUVE=0xffcba6f7
RED=0xfff38ba8
GREEN=0xffa6e3a1
YELLOW=0xfff9e2af
BLUE=0xff89b4fa
TRANSPARENT=0x00000000

# Glass bar: the Ghostty background (base) at the same 85% opacity, with a faint light edge.
BAR_COLOR=0xd91e1e2e
BAR_BORDER=0x26ffffff

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
