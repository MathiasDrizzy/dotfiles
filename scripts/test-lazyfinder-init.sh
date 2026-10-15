#!/usr/bin/env bash
# Test of the lazyfinder shell integration in mac/zshrc (order 2026-10-14-14).
# Everything runs in a temporary HOME/ZDOTDIR with a fake lazyfinder; it never touches the real HOME.
#  L1  lazyfinder on PATH     -> the lazyfinder function is defined and the shell ends in the folder it writes
#  L3  a newer lazyfinder binary             -> the cached init is regenerated
#  L2  lazyfinder not on PATH -> the shell starts with rc=0, no lazyfinder error and no function
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fails=0
check() { # name, command...
  local name="$1"
  shift
  if "$@"; then printf '  PASS  [L] %s\n' "$name"; else
    printf '  FAIL  [L] %s\n' "$name"
    fails=$((fails + 1))
  fi
}
not() { ! "$@"; }
contains() { [[ "$1" == *"$2"* ]]; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home" "$T/zdot" "$T/bin" "$T/target"
printf 'source %q\n' "$ROOT/mac/zshrc" >"$T/zdot/.zshrc"

# Fake lazyfinder: --shell-init prints the same wrapper the real one prints; otherwise it writes a folder to --cwd-file.
cat >"$T/bin/lazyfinder" <<FAKE
#!/bin/sh
if [ "\$1" = "--shell-init" ]; then
  cat <<'INIT'
lazyfinder() {
  local cwd_file cwd code
  cwd_file="\$(mktemp -t lazyfinder-cwd.XXXXXX)" || return
  command lazyfinder --cwd-file "\$cwd_file" "\$@"
  code=\$?
  cwd="\$(command cat -- "\$cwd_file")"
  if [ -n "\$cwd" ] && [ "\$cwd" != "\$PWD" ] && [ -d "\$cwd" ]; then
    builtin cd -- "\$cwd" || code=\$?
  fi
  command rm -f -- "\$cwd_file"
  return \$code
}
INIT
  exit 0
fi
[ "\$1" = "--cwd-file" ] && printf '%s' "$T/target" >"\$2"
FAKE
chmod +x "$T/bin/lazyfinder"

run_zsh() { # extra PATH entry, command
  env -i HOME="$T/home" ZDOTDIR="$T/zdot" PATH="$1:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" TERM=xterm \
    zsh -i -c "$2" 2>"$T/err"
}

out="$(run_zsh "$T/bin" 'whence -w lazyfinder; cd /; lazyfinder; pwd -P')"
check "with lazyfinder: the function is defined" contains "$out" "lazyfinder: function"
check "with lazyfinder: the shell ends in the folder lazyfinder wrote" test "$(printf %s "$out" | tail -1)" = "$(cd "$T/target" && pwd -P)"

# A newer binary regenerates the cache (the fake prints a marker comment once it is "upgraded").
sed -i '' 's|^  cat <<.INIT.$|  echo "# v2"; cat <<'"'"'INIT'"'"'|' "$T/bin/lazyfinder"
sleep 1
touch "$T/bin/lazyfinder"
run_zsh "$T/bin" 'true' >/dev/null
check "newer binary: the cached init is regenerated" grep -q "# v2" "$T/home/.cache/lazyfinder-init.zsh"

# Hide any real lazyfinder: a PATH that has only the system dirs.
out2="$(env -i HOME="$T/home" ZDOTDIR="$T/zdot" PATH="/usr/bin:/bin:/usr/sbin:/sbin" TERM=xterm zsh -i -c 'whence -w lazyfinder; echo rc-ok' 2>"$T/err")"
check "without lazyfinder: the shell starts" contains "$out2" "rc-ok"
check "without lazyfinder: no function is defined" not contains "$out2" "lazyfinder: function"
check "without lazyfinder: no error mentions lazyfinder" not grep -qi lazyfinder "$T/err"

if [ "$fails" -eq 0 ]; then echo "test-lazyfinder-init: PASS"; else
  echo "test-lazyfinder-init: $fails FAIL"
  exit 1
fi
