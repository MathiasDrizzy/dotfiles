#!/usr/bin/env bash
# Harness rápido (C2, C3, C4 y chequeos de sintaxis). Lo usan el pre-commit y el stop-gate del agente.
# No necesita red ni abre herdr. El harness de comportamiento (lento) es scripts/harness-behavior.py.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

fail=0
step() { printf '\n==> %s\n' "$1"; }
bad()  { echo "✗ $1" >&2; fail=1; }

step "C2: sin IPs de LAN, hostnames ni rutas de DNS-blocker en archivos versionados"
# El patrón usa clases de caracteres ([.], [o]…) para que este mismo archivo no lo cumpla.
# Los archivos borrados en el índice (git rm) no existen en disco: se excluyen.
files=()
while IFS= read -r f; do [ -f "$f" ] && files+=("$f"); done < <(git ls-files)
if [ "${#files[@]}" -gt 0 ] && grep -nE '192[.]168[.]|pizer[o]|setpasswor[d]|/admi[n]' "${files[@]}"; then
  bad "datos de red local o de DNS-blocker en el árbol (ver líneas arriba)"
else
  echo "✓ limpio"
fi

step "Sintaxis de scripts (bash -n) y TOML"
for f in $(git ls-files '*.sh' 'scripts/hooks/*' 'mac/install.sh' 'mac/zshrc' 'mac/zshenv' | sort -u); do
  [ -f "$f" ] || continue
  case "$f" in mac/zshrc|mac/zshenv) shell=zsh ;; *) shell=bash ;; esac
  command -v "$shell" >/dev/null || continue
  "$shell" -n "$f" 2>/dev/null || bad "sintaxis inválida en $f"
done
# Un script con shebang debe ir con modo 755 en el índice (un clon nuevo lo recibe tal cual).
while read -r mode _ _ f; do
  [ -f "$f" ] || continue
  if [ "$(head -c2 "$f")" = "#!" ] && [ "$mode" != "100755" ]; then bad "$f tiene shebang pero modo $mode (debe ser 100755)"; fi
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
        print(f"✗ TOML inválido en {f}: {e}", file=sys.stderr); bad = 1
sys.exit(bad)
PY
[ "$fail" -eq 0 ] && echo "✓ ok"

step "C3: herdr-ctl (gofmt, go vet, go test)"
(
  cd mac/tools/herdr-ctl || exit 1
  unformatted="$(gofmt -l .)"
  [ -z "$unformatted" ] || { echo "gofmt pendiente en: $unformatted" >&2; exit 1; }
  go vet ./... && go test ./...
) || bad "herdr-ctl falla"

step "C4: conflictos de atajos contra los defaults de herdr"
if command -v herdr >/dev/null; then
  (cd mac/tools/herdr-ctl && HERDR_CONFIG_PATH="$PWD/../../config/herdr/config.toml" go run . keys-check) || bad "keys-check con conflictos sin resolver"
else
  echo "herdr no está instalado: se omite (los tests usan el fixture congelado)"
fi

echo
if [ "$fail" -eq 0 ]; then echo "harness-quick: PASS"; else echo "harness-quick: FAIL" >&2; fi
exit "$fail"
