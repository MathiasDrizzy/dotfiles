#!/usr/bin/env bash
# Repository checks CI runs before the sandboxed install: nothing private in a public repo, script syntax and modes,
# valid TOML, and the config tests that need no network (zshenv, lazyfinder, AeroSpace). No network, no real HOME.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

fail=0
step() { printf '\n==> %s\n' "$1"; }
bad() {
  echo "✗ $1" >&2
  fail=1
}

files=()
# Files deleted in the index (git rm) are not on disk: skipped.
while IFS= read -r f; do [ -f "$f" ] && files+=("$f"); done < <(git ls-files)

step "Public repo: no local network addresses, internal services or precise coordinates"
# Character classes ([.], [o]...) keep this file from matching its own patterns.
if grep -nE '192[.]168[.]|pizer[o]|setpasswor[d]|/admi[n]' "${files[@]}"; then
  bad "local network or internal service data in tracked files (lines above)"
fi
# A latitude and longitude with four or more decimals (meters) place a home. Fixtures use Plaza de Armas in Santiago, a
# public landmark, or whole degrees.
# Separators: commas, quotes, blanks and an escaped tab (\t in a string literal).
if grep -nE -- '-?[0-9]{1,3}[.][0-9]{4,}([",[:space:]]|\\t)+(longitude:[[:space:]]*|"longitude":"?)?-?[0-9]{1,3}[.][0-9]{4,}' \
  "${files[@]}" | grep -vE -- '-33[.]4378[0-9]*([",[:space:]]|\\t)+(longitude:[[:space:]]*)?-70[.]650[0-9]*'; then
  bad "precise coordinates in tracked files (lines above): use Plaza de Armas (-33.437800, -70.650500) in fixtures"
fi

step "Script syntax (bash -n, zsh -n), executable modes and TOML"
for f in $(git ls-files '*.sh' 'mac/install.sh' 'mac/zshrc' 'mac/zshenv' | sort -u); do
  [ -f "$f" ] || continue
  case "$f" in mac/zshrc | mac/zshenv) shell=zsh ;; *) shell=bash ;; esac
  command -v "$shell" >/dev/null || continue
  "$shell" -n "$f" 2>/dev/null || bad "invalid syntax in $f"
done
# A script with a shebang goes in the index with mode 755: a fresh clone gets it as is.
while read -r mode _ _ f; do
  [ -f "$f" ] || continue
  if [ "$(head -c2 "$f")" = "#!" ] && [ "$mode" != "100755" ]; then bad "$f has a shebang but mode $mode (must be 100755)"; fi
done < <(git ls-files -s)
python3 - <<'PY' || fail=1
import subprocess, sys, tomllib
bad = 0
for f in subprocess.run(["git", "ls-files", "*.toml"], capture_output=True, text=True).stdout.split():
    try:
        tomllib.load(open(f, "rb"))
    except FileNotFoundError:
        continue
    except Exception as e:
        print(f"✗ invalid TOML in {f}: {e}", file=sys.stderr); bad = 1
sys.exit(bad)
PY

step "Config tests (temporary HOME)"
scripts/test-zshenv.sh >/dev/null || bad "test-zshenv fails (run it for details)"
scripts/test-lazyfinder-init.sh >/dev/null || bad "test-lazyfinder-init fails (run it for details)"
scripts/test-aerospace-config.sh >/dev/null || bad "test-aerospace-config fails (run it for details)"

echo
if [ "$fail" -eq 0 ]; then echo "check-repo: PASS"; else echo "check-repo: FAIL"; fi
exit "$fail"
