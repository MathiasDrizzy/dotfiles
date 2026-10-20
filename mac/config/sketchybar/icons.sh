# shellcheck shell=bash disable=SC2034
# Icon glyphs: every one is a sketchybar-app-font ligature (the same pack as the app glyphs in icon_map.sh),
# so the whole bar shares one icon font. Sourced by sketchybarrc and the plugins.

# One size per kind for the whole bar: icons 15, text 12 (workspace numbers and the clock are bold, the rest regular).
ICON_SIZE=15.0
TEXT_SIZE=12.0
APPLE_SIZE=18.0 # the logo has more padding inside its glyph box than the pack glyphs
ARROW_SIZE=11.0 # chevron glyphs are drawn larger than the rest of the pack, so they get a smaller size to look equal

APP_ICON_FONT="sketchybar-app-font"
# The pack has no Apple logo; this one is U+F8FF from the macOS system font, drawn at the same size and color.
APPLE_FONT="System Font"
APPLE=$'\xef\xa3\xbf'
PLAY=':playing:'
PAUSE=':paused:'
PREV=':chevron_left:'
NEXT=':chevron_right:'
CPU=':cpu:'
RAM=':ram:'
BAT_CHARGING=':charging:'
# The pack has no battery shape, so the battery levels (and RESTART) come from the Nerd Font Material set.
NERD_FONT="JetBrainsMono Nerd Font"
BAT_0='󰂎'
BAT_10='󰁺'
BAT_20='󰁻'
BAT_30='󰁼'
BAT_40='󰁽'
BAT_50='󰁾'
BAT_60='󰁿'
BAT_70='󰂀'
BAT_80='󰂁'
BAT_90='󰂂'
BAT_100='󰁹'
CONTROL=':widget:' # opens Control Center
CHEVRON_LEFT=':chevron_left:'
CHEVRON_RIGHT=':chevron_right:'
SETTINGS=':gear:'
ICON_INFO=':system_information:'
SLEEP=':moon:'
LOCK=':vpn:'
LOGOUT=':close:'
RESTART='󰜉' # the pack has no restart arrow either: Nerd Font Material glyph
POWER=':cancel:'
