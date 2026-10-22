# shellcheck shell=bash disable=SC2034
# Icon glyphs: the app glyphs (icon_map.sh) and a few others are sketchybar-app-font ligatures; the status items and both
# menus use neutonfoo/dotfiles's JetBrainsMono Nerd Font glyphs. Sourced by sketchybarrc and the plugins.

# One size per kind for the whole bar: icons 15, text 12 (workspace numbers and the clock are bold, the rest regular).
ICON_SIZE=15.0
TEXT_SIZE=12.0
MOON_SIZE=22.0 # his moon phase glyph
SPOTIFY_SIZE=20.0 # his Spotify logo
APPLE_SIZE=18.0 # the logo has more padding inside its glyph box than the pack glyphs

APP_ICON_FONT="sketchybar-app-font"
# The pack has no Apple logo; this one is U+F8FF from the macOS system font, drawn at the same size and color.
APPLE_FONT="System Font"
APPLE=$'\xef\xa3\xbf'
CPU=':cpu:'
RAM=':ram:'
# Battery, Spotify, weather, moon and clock glyphs are neutonfoo/dotfiles's (Nerd Font: fa-battery_*, fa-bolt, fa-spotify,
# fa-thermometer, weather moon phases, md-calendar_clock); the menus' are Material Design ones from the same font.
NERD_FONT="JetBrainsMono Nerd Font"
BAT_FULL=''
BAT_THREE_QUARTERS=''
BAT_HALF=''
BAT_QUARTER=''
BAT_EMPTY=''
BAT_CHARGING=''
SPOTIFY=''
MEDIA_DOT='' # between the title and the artist
WEATHER=''
# The moon box left of the weather: the eight phases, new moon first (weather icons).
MOON_PHASES=('' '' '' '' '' '' '' '')
CONTROL=':widget:' # opens Control Center
TIME='󰥔'           # the time and the date (Nerd Font, md-clock_outline / md-calendar_clock)
CALENDAR='󰃰'
POWERLINE_ARROW=$'\xee\x82\xb0' # the arrow after the front app's block (Nerd Font, pl-right_hard_divider)
ARROW_BLOCK_SIZE=19.5 # his look (measured against his screenshot): as tall as the block, its slope starting on the rounded corners
VORSSAINT=''      # opens Vorssaint's menu: a planet, like its own icon (Nerd Font, fae-planet)
CHEVRON_LEFT='󰅁' # md-chevron_left
CHEVRON_RIGHT='󰅂' # md-chevron_right
SETTINGS='󰢻' # md-cog_outline
ICON_INFO='󰋽' # md-information_outline
SLEEP='󰖔' # md-weather_night
LOCK='󰍁' # md-lock_outline
LOGOUT='󰍃' # md-logout
RESTART='󰜉' # md-restart
POWER='󰐥' # md-power
