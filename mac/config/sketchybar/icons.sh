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
# The pack has no battery shape, so the battery levels come from the Nerd Font Material set (same weight and size).
BAT_FONT="JetBrainsMono Nerd Font"
BAT_0=$'\U000F008E'
BAT_10=$'\U000F007A'
BAT_20=$'\U000F007B'
BAT_30=$'\U000F007C'
BAT_40=$'\U000F007D'
BAT_50=$'\U000F007E'
BAT_60=$'\U000F007F'
BAT_70=$'\U000F0080'
BAT_80=$'\U000F0081'
BAT_90=$'\U000F0082'
BAT_100=$'\U000F0079'
WIFI=':wifi:'
WIFI_OFF=':wifi_off:'
CHEVRON_LEFT=':chevron_left:'
CHEVRON_RIGHT=':chevron_right:'
SETTINGS=':gear:'
ICON_INFO=':system_information:'
SLEEP=':moon:'
LOCK=':vpn:'
LOGOUT=':close:'
RESTART=':statistics:'
POWER=':cancel:'
