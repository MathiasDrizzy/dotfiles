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
    case "$v" in CONFIG_DIR | PLUGIN_DIR | FONT | HOME | NAME | INFO | FOCUSED_WORKSPACE | NF | SENDER | MAX_ENTRIES | SELF) continue ;; esac
    grep -q "^$v=" "$SB/colors.sh" "$SB/icons.sh" || {
      echo "undefined: $v" >&2
      return 1
    }
  done
}
no_event_var_shadowing() { # colors.sh and icons.sh are sourced by scripts that also read SketchyBar's event variables
  ! grep -qE '^(INFO|SENDER|NAME|BUTTON|MODIFIER|SCROLL_DELTA|FOCUSED_WORKSPACE)=' "$SB/colors.sh" "$SB/icons.sh"
}
transparent_bar() {
  grep -q 'color=\$TRANSPARENT' "$SB/sketchybarrc" && grep -q 'notch_width=' "$SB/sketchybarrc"
}
aerospace_hooks() {
  local c="$ROOT/mac/config/aerospace/aerospace.toml"
  grep -q "exec-and-forget sketchybar'" "$c" && grep -q 'sketchybar --trigger aerospace_workspace_change' "$c"
}
installer_ok() {
  local f
  grep -q 'brew install felixkratz/formulae/sketchybar' "$ROOT/mac/install.sh" &&
    grep -q 'brew install ungive/media-control/media-control' "$ROOT/mac/install.sh" || return 1
  for f in sketchybarrc colors.sh icons.sh plugins/aerospace.sh plugins/media.sh plugins/toggle.sh; do
    grep -q "config/sketchybar/$f|" "$ROOT/mac/scripts/check-links.sh" || return 1
  done
}

check "all scripts parse" syntax_ok
check "the rc and the plugins are executable" executable_ok
check "every plugin the rc points to exists" plugins_exist
check "every icon and color used is defined" symbols_defined
check "colors.sh and icons.sh do not shadow SketchyBar event variables" no_event_var_shadowing
check "the bar is transparent and keeps the notch gap" transparent_bar
check "AeroSpace starts SketchyBar and triggers workspace changes" aerospace_hooks
check "install.sh installs the formulae and check-links.sh links the files" installer_ok

if [ "$fails" -eq 0 ]; then echo "test-sketchybar-config: PASS"; else
  echo "test-sketchybar-config: $fails FAIL"
  exit 1
fi
