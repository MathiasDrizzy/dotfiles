#!/usr/bin/env bash
# Test del stop-gate (ORD-dotfiles-005 D1): comportamiento de `.claude/rojo-declarado`.
# Usa un repo temporal con un harness falso que imprime los fallos en los formatos reales
# (`--- FAIL: TestX` de Go, `  FAIL  descripción  [cmd]` de test-zshenv, `✗ …` de harness-quick).
# El hook vive en .claude/ (ignorado por git): si no existe en este clon, el test se omite.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/.claude/hooks/stop-gate.sh"
[ -f "$HOOK" ] || { echo "test-stop-gate: SKIP (no hay .claude/hooks/stop-gate.sh en este clon)"; exit 0; }

fails=0; TMPS=()
ok()   { printf '  PASS  %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }
cleanup() { for t in ${TMPS[@]+"${TMPS[@]}"}; do rm -rf "$t"; done; }
trap cleanup EXIT

# newfix: deja en $T un repo con el hook, un harness falso y la marca de "último stop" ya creada.
newfix() {
  T="$(mktemp -d "${TMPDIR:-/tmp}/stopgate-test.XXXXXX")"; TMPS+=("$T")
  mkdir -p "$T/.claude/hooks" "$T/scripts" "$T/tmp"
  cp "$HOOK" "$T/.claude/hooks/stop-gate.sh"
  printf '.claude/\nESTADO.md\n' > "$T/.gitignore"
  cat > "$T/scripts/harness-quick.sh" <<'EOF'
#!/usr/bin/env bash
# Harness falso: cada línea de falla.txt es "go:NombreTest", "zsh:descripción" u "otro".
cd "$(dirname "$0")/.." || exit 2
[ -s falla.txt ] || { echo "harness-quick: PASS"; exit 0; }
while IFS= read -r l; do
  case "$l" in
    go:*)  echo "--- FAIL: ${l#go:} (0.00s)"; echo "    x_test.go:1: falló" ;;
    zsh:*) printf '  FAIL  %s\t[%s]\n' "${l#zsh:}" "cmd con  dos espacios y [corchetes]" ;;
    build) echo "# paquete [build failed]"; echo "FAIL	paquete [build failed]" ;;
    gofmt) echo "gofmt pendiente en: x_test.go" ;;
    pkgbuild) echo "FAIL	otro/paquete [build failed]" ;;
    stopgate) echo "✗ test-stop-gate falla" ;;
    ruido) echo "  PASS  22 ejemplo de salida ajena ([build failed]) y panic: en medio de una línea" ;;
    gosub:*) echo "    --- FAIL: ${l#gosub:} (0.00s)" ;;
    zshbuild) echo "test-zshenv.sh: línea 3: error de sintaxis" ;;
    otro)  echo "✗ datos de red local en el árbol" ;;
  esac
done < falla.txt
grep -q '^go:' falla.txt && echo "✗ herdr-ctl falla"
grep -q '^zsh:' falla.txt && echo "✗ test-zshenv falla"
grep -qE '^(build|gofmt)' falla.txt && echo "✗ herdr-ctl falla"
grep -q '^zshbuild' falla.txt && echo "✗ test-zshenv falla"
echo "harness-quick: FAIL"; exit 1
EOF
  chmod +x "$T/scripts/harness-quick.sh" "$T/.claude/hooks/stop-gate.sh"
  ( cd "$T" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm base )
  : > "$T/falla.txt"
  hook >/dev/null 2>&1          # primera ejecución: crea la marca
  sleep 1
}
hook() { # corre el hook en $T; deja rc en $RC y stderr en $ERR
  ERR="$(cd "$T" && printf '{"session_id":"t"}' | CLAUDE_PROJECT_DIR="$T" TMPDIR="$T/tmp" bash .claude/hooks/stop-gate.sh 2>&1 >/dev/null)"; RC=$?
}
cambio() { echo "x" >> "$T/a.txt"; touch "$T/ESTADO.md"; }   # cambio del turno + ESTADO al día
rojo()   { printf '%s\n' "$@" > "$T/.claude/rojo-declarado"; }
falla()  { printf '%s\n' "$@" > "$T/falla.txt"; }
caso()   { # caso <nombre> <rc esperado> [texto esperado en stderr]
  local n="$1" want="$2" txt="${3:-}"
  if [ "$RC" -eq "$want" ] && { [ -z "$txt" ] || printf '%s' "$ERR" | grep -qi -- "$txt"; }; then ok "$n (rc=$RC)"
  else fail "$n: rc=$RC (esperado $want${txt:+, stderr con '$txt'})  stderr=[$(printf '%s' "$ERR" | head -c 200)]"; fi
}

echo "== Casos de siempre (sin rojo declarado)"
newfix; cambio; hook;                                caso "1 harness en verde, cambio del turno → pasa" 0
newfix; cambio; falla "go:TestA"; hook;              caso "2 test en rojo sin declarar → bloquea" 2 "herdr-ctl falla"
newfix; hook;                                        caso "3 sin cambios en el turno → pasa" 0
newfix; cambio; falla "go:TestA"; touch "$T/.claude/esperando"; hook; caso "4 en espera → pasa" 0

echo "== Rojo declarado (D1)"
newfix; cambio; falla "go:TestA" "go:TestB"; rojo "TestA  # fase roja TDD" "TestB  # idem"; hook
caso "8 rojo declarado con la lista exacta → pasa" 0
newfix; cambio; falla "go:TestA" "go:TestC"; rojo "TestA  # fase roja"; hook
caso "9 rojo declarado + otro test que falla → bloquea" 2
newfix; cambio; falla "go:TestA"; rojo "TestA  # fase roja"; touch -t 202001010000 "$T/.claude/rojo-declarado"; hook
caso "10 declaración vencida (>24 h) → bloquea con aviso" 2 "vencid"
newfix; cambio; falla "go:TestA"; rojo "TestA  # fase roja" "TestInexistente  # no existe"; hook
caso "11 declaración con un test inexistente → pasa, con aviso" 0 "TestInexistente"
newfix; cambio; falla "go:TestA" "otro"; rojo "TestA  # fase roja"; hook
caso "12 rojo declarado + falla NO de tests (datos de red) → bloquea" 2
newfix; cambio; falla "build"; rojo "TestA  # fase roja"; hook
caso "13 error de compilación (sin test con nombre) → bloquea aunque haya declaración" 2
newfix; cambio; falla "zsh:[Z2-dry-run] corrida 1: rc=0"; rojo "[Z2-dry-run] corrida 1: rc=0  # fase roja"; hook
caso "14 rojo declarado con un check de test-zshenv (nombre con espacios) → pasa" 0
newfix; cambio; rojo "TestA  # ya pasa"; hook
caso "15 harness en verde y declaración sobrante → pasa, con aviso" 0 "TestA"
newfix; cambio; falla "go:TestA"; rojo "# solo comentarios" ""; hook
caso "16 archivo sin entradas → bloquea" 2
newfix; falla "go:TestA"; rojo "TestA  # rojo"; echo "x" >> "$T/a.txt"; hook
caso "17 rojo declarado pero ESTADO viejo → sigue bloqueando por ESTADO" 2 "ESTADO"

newfix; cambio; falla "zsh:[Z2] a" "build"; rojo "[Z2] a  # fase roja"; hook
caso "18 check de zshenv declarado + herdr-ctl falla SIN tests con nombre (compilación) → bloquea" 2
newfix; cambio; falla "zsh:[Z2] a" "gofmt"; rojo "[Z2] a  # fase roja"; hook
caso "19 check declarado + gofmt pendiente (herdr-ctl falla sin tests) → bloquea" 2
newfix; cambio; falla "go:TestA" "zshbuild"; rojo "TestA  # fase roja"; hook
caso "20 test de Go declarado + test-zshenv falla sin checks con nombre → bloquea" 2
newfix; cambio; falla "go:TestA" "zsh:[Z2] a"; rojo "TestA  # r" "[Z2] a  # r"; hook
caso "21 un test de Go y un check de zshenv, ambos declarados → pasa" 0

newfix; cambio; falla "go:TestA" "pkgbuild"; rojo "TestA  # fase roja"; hook
caso "22 test declarado + otro paquete que no compila ([build failed]) → bloquea" 2
newfix; cambio; falla "go:TestA" "stopgate"; rojo "TestA  # fase roja"; hook
caso "23 test declarado + falla del propio test-stop-gate → bloquea (no se puede declarar)" 2
newfix; cambio; falla "zsh:[Z2] check issue #123"; rojo "[Z2] check issue #123  # motivo"; hook
caso "24 nombre con '#' declarado (el motivo va tras ' # ') → pasa" 0
newfix; cambio; falla "go:TestPadre" "gosub:TestPadre/Sub"; rojo "TestPadre  # fase roja"; hook
caso "25 declarar el test padre cubre sus subtests (por diseño: se declara el nivel superior) → pasa" 0

newfix; cambio; falla "go:TestA" "ruido"; rojo "TestA  # fase roja"; hook
caso "26 texto '[build failed]' dentro de una línea ajena (p. ej. la salida de otro test) NO cuenta como compilación fallida → pasa" 0

echo
if [ "$fails" -eq 0 ]; then echo "test-stop-gate: PASS"; else echo "test-stop-gate: $fails FAIL" >&2; fi
exit "$fails"
