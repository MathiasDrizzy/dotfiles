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

# The right-hand panel (toggle.sh) keeps its state in these files; plugins that paint its items must not write colors while it
# is hidden or animating (a color written mid-fade left icons and numbers floating).
PANEL_STATE="$HOME/.cache/sketchybar/panel"
PANEL_BUSY="$HOME/.cache/sketchybar/panel_busy"
panel_idle() { [ "$(cat "$PANEL_STATE" 2>/dev/null)" = on ] && [ ! -e "$PANEL_BUSY" ]; }
