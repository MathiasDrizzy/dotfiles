#!/usr/bin/env bash
# Test of mac/config/aerospace/aerospace.toml (pure file checks, never touches the real AeroSpace or HOME).
#  A1  the file parses as TOML and declares config-version 2
#  A2  no binding uses alt-b, alt-f or alt-d: zsh/readline word motions (Option is Alt in Ghostty) must keep working
#  A3b no binding uses the vim keys h, j, k or l (Mathias does not use vim-style keys: arrows instead)
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
  local n
  while read -r mode key cmd; do
    [ "$mode" = main ] || continue
    case "$cmd" in "workspace "[0-9]*) n="${cmd#workspace }" ;; *) continue ;; esac
    bindings | grep -q "^main alt-shift-${key#alt-} move-node-to-workspace $n\$" || return 1
  done < <(bindings)
}
no_readline_keys() { bindings | awk '$1=="main" && $2 ~ /^(alt-b|alt-f|alt-d|alt-shift-b|alt-shift-f|alt-shift-d)$/ {found=1} END{exit found?0:1}'; }
callbacks() { python3 -I -c 'import sys,tomllib
d=tomllib.load(open(sys.argv[1],"rb")); c=d.get("on-window-detected", [])
sys.exit(0 if isinstance(c,list) and all(isinstance(x,dict) and "run" in x and set(x)<={"if","run","check-further-callbacks"} for x in c) else 1)' "$CFG"; }
no_vim_keys() { bindings | awk '$2 ~ /^(alt|ctrl|cmd)?(-shift)?-?[hjkl]$/ || $2 ~ /-[hjkl]$/ {found=1} END{exit found?0:1}'; }
installer_links() {
  grep -q 'config/aerospace/aerospace.toml' "$ROOT/mac/install.sh" &&
    grep -q 'config/aerospace/aerospace.toml|' "$ROOT/mac/scripts/check-links.sh" &&
    grep -q 'brew install --cask nikitabobko/tap/aerospace' "$ROOT/mac/install.sh"
}

check "the config parses as TOML (config-version 2)" parses
check "no binding steals alt-b, alt-f or alt-d from the shell" not no_readline_keys
check "no binding uses the vim keys h, j, k or l" not no_vim_keys
check "each workspace binding has a move-node-to-workspace twin" twins
check "on-window-detected callbacks have the documented shape" callbacks
check "install.sh and check-links.sh link the config and install the cask" installer_links

if [ "$fails" -eq 0 ]; then echo "test-aerospace-config: PASS"; else
  echo "test-aerospace-config: $fails FAIL"
  exit 1
fi
