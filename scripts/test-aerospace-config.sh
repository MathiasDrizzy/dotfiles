#!/usr/bin/env bash
# Test of mac/config/aerospace/aerospace.toml (pure file checks, never touches the real AeroSpace or HOME).
#  A1  the file parses as TOML and declares config-version 2
#  A2  no binding uses alt-b, alt-f or alt-d: zsh/readline word motions (Option is Alt in Ghostty) must keep working
#  A3b no binding uses the vim keys h, j, k or l (Mathias does not use vim-style keys: arrows instead)
#  A3c no binding uses the US punctuation keys (minus, equal, slash, semicolon, quote, brackets, backslash, backtick):
#      Mathias's keyboard is Latin American, where those physical keys carry other symbols; the config aliases them
#  A3  every workspace binding has its move-node-to-workspace twin
#  A4  on-window-detected callbacks have the documented shape (list of {if, run} objects)
#  A5  the installer links the config (REQUIRED_SOURCES, CONFIG_PAIRS) and installs the cask
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CFG="$ROOT/mac/config/aerospace/aerospace.toml"
fails=0
check() { # name, command...
  local name="$1"
  shift
  if "$@"; then printf '  PASS  [A] %s\n' "$name"; else
    printf '  FAIL  [A] %s\n' "$name"
    fails=$((fails + 1))
  fi
}
not() { ! "$@"; }

parses() { python3 -I -c 'import sys,tomllib; d=tomllib.load(open(sys.argv[1],"rb")); sys.exit(0 if d.get("config-version")==2 else 1)' "$CFG"; }
bindings() { python3 -I -c 'import sys,tomllib
d=tomllib.load(open(sys.argv[1],"rb"))
for mode,m in d.get("mode",{}).items():
    for k,v in m.get("binding",{}).items(): print(mode, k, v if isinstance(v,str) else ";".join(v))' "$CFG"; }
twins() {
  local n twin
  while read -r mode key cmd; do
    [ "$mode" = main ] || continue
    case "$cmd" in "workspace "[0-9e]*) n="${cmd#workspace }" ;; *) continue ;; esac
    case "$key" in
    alt-*) twin="alt-shift-${key#alt-}" ;;
    ctrl-alt-*) twin="ctrl-alt-shift-${key#ctrl-alt-}" ;;
    *) continue ;;
    esac
    bindings | grep -q "^main $twin move-node-to-workspace $n\$" || return 1
  done < <(bindings)
}
has_snail() { bindings | grep -q "^main alt-shift-s .*flatten-workspace-tree.*focus --dfs-index 1.*join-with right"; }
no_readline_keys() { bindings | awk '$1=="main" && $2 ~ /^(alt-b|alt-f|alt-d|alt-shift-b|alt-shift-f|alt-shift-d)$/ {found=1} END{exit found?0:1}'; }
callbacks() { python3 -I -c 'import sys,tomllib
d=tomllib.load(open(sys.argv[1],"rb")); c=d.get("on-window-detected", [])
sys.exit(0 if isinstance(c,list) and all(isinstance(x,dict) and "run" in x and set(x)<={"if","run","check-further-callbacks"} for x in c) else 1)' "$CFG"; }
no_vim_keys() { bindings | awk '$2 ~ /^(alt|ctrl|cmd)?(-shift)?-?[hjkl]$/ || $2 ~ /-[hjkl]$/ {found=1} END{exit found?0:1}'; }
no_us_punctuation() { bindings | awk '$2 ~ /-(minus|equal|slash|backslash|semicolon|quote|backtick|leftSquareBracket|rightSquareBracket)$/ {found=1} END{exit found?0:1}'; }
installer_links() {
  grep -q 'config/aerospace/aerospace.toml' "$ROOT/mac/install.sh" &&
    grep -q 'config/aerospace/aerospace.toml|' "$ROOT/mac/scripts/check-links.sh" &&
    grep -q 'brew install --cask nikitabobko/tap/aerospace' "$ROOT/mac/install.sh"
}

check "the config parses as TOML (config-version 2)" parses
check "no binding steals alt-b, alt-f or alt-d from the shell" not no_readline_keys
check "alt-shift-s arranges the workspace as a snail (big left, two stacked right)" has_snail
check "no binding uses the vim keys h, j, k or l" not no_vim_keys
check "no binding uses US punctuation keys (Latin American keyboard)" not no_us_punctuation
check "each workspace binding has a move-node-to-workspace twin" twins
check "on-window-detected callbacks have the documented shape" callbacks
# Resizing a window with the mouse made AeroSpace report a monitor change, and the callback threw the pointer to the middle of the screen.
not_warping_pointer() { ! grep -q "^on-focused-monitor-changed" "$CFG"; }
check "a focused-monitor change never moves the pointer (it jumped mid-resize)" not_warping_pointer
# The border is turned off for now (the user's choice): its start stays in the config, commented out, ready to come back.
has_borders() {
  ! grep -q "^after-startup-command" "$CFG" && grep -q "^# after-startup-command = \\[" "$CFG" &&
    grep -q "^#.*exec-and-forget borders .*style=round" "$CFG" && grep -q "inactive_color=0x00000000" "$CFG" &&
    grep -q 'brew install felixkratz/formulae/borders' "$ROOT/mac/install.sh"
}
check "the focused window's round border is off, ready to uncomment (borders, installed by install.sh)" has_borders
check "install.sh and check-links.sh link the config and install the cask" installer_links
# Vorssaint lives in its menu: a settings window it opens tiled the workspace and squeezed the windows under its menu.
vorssaint_floats() { grep -q "{ if = 'test %{app-bundle-id} = com.vorssaint.utils', run = 'layout floating' }" "$CFG"; }
check "Vorssaint's windows float instead of tiling" vorssaint_floats

# The external monitor has its own nine workspaces, drawn as 1 to 9 on the bar: Option+N for the Mac's, Control+Option+N for
# the external's (named eN in the config, pinned to the secondary monitor, falling back to the main one without it).
external_nine() {
  local n
  for n in 1 2 3 4 5 6 7 8 9; do
    bindings | grep -q "^main ctrl-alt-$n workspace e$n\$" || return 1
    python3 -I -c 'import sys,tomllib
d=tomllib.load(open(sys.argv[1],"rb")); n=sys.argv[2]
a=d.get("workspace-to-monitor-force-assignment",{})
sys.exit(0 if a.get("e"+n)==["secondary","main"] and a.get(n)=="main" and "e"+n in d.get("persistent-workspaces",[]) else 1)' "$CFG" "$n" || return 1
  done
}
check "Control+Option+1..9 reach the external monitor's workspaces e1..e9, pinned to it" external_nine

if [ "$fails" -eq 0 ]; then echo "test-aerospace-config: PASS"; else
  echo "test-aerospace-config: $fails FAIL"
  exit 1
fi
