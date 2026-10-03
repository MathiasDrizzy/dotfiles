#!/usr/bin/env bash
# Test de ~/.zshenv (ORD-dotfiles-004, Z1–Z4). Todo ocurre en un HOME temporal; nunca toca el HOME real.
#  Z1  sin ~/.zshenv + install.sh --links-only        -> no se crea
#  Z2  con ~/.zshenv propio + cada modo               -> el contenido se conserva (intacto o respaldado)
#  Z3  check-links.sh sin --fix                       -> informa el estado real, sin falso OK
#  Z4  dos corridas seguidas de cada modo             -> idempotente, rc=0, sin enlaces rotos
# El modo completo de install.sh instala paquetes globales, así que su parte de enlaces se prueba
# con `check-links.sh --fix` (es exactamente lo que install.sh ejecuta en el paso 6).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$ROOT/mac/install.sh"
LINKS="$ROOT/mac/scripts/check-links.sh"
OWN='export MI_VAR=propia  # contenido del usuario'

fails=0
ok()   { printf '  PASS  %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1  [$2]"; fi; }

# Para que `go` (dry-run de install.sh) no cree un caché de módulos de solo lectura en el HOME temporal.
export GOMODCACHE="$(go env GOMODCACHE)" GOCACHE="$(go env GOCACHE)" GOPATH="$(go env GOPATH)"

TMPS=()
newhome() { # deja la ruta en $T (sin subshell, para que cleanup la conozca)
  T="$(mktemp -d "${TMPDIR:-/tmp}/zshenv-test.XXXXXX")"; TMPS+=("$T"); mkdir -p "$T/home"
}
cleanup() { for t in ${TMPS[@]+"${TMPS[@]}"}; do chmod -R u+w "$t" 2>/dev/null; rm -rf "$t"; done; }
trap cleanup EXIT

run() { # run <home> <backup> <cmd...>   (salida en $OUT, rc en $RC)
  local h="$1" b="$2"; shift 2
  OUT="$(HOME="$h" DOTFILES_BACKUP_DIR="$b" "$@" 2>&1)"; RC=$?
}
broken_links() { find "$1" -type l ! -exec test -e {} \; -print 2>/dev/null | grep -v '/go/' | wc -l | tr -d ' '; }
strip() { sed 's/\x1b\[[0-9;]*m//g'; }

echo "== Z1: HOME sin ~/.zshenv + --links-only"
newhome; H="$T/home"; B="$T/respaldos"
run "$H" "$B" "$INSTALL" --links-only
check "rc=0" '[ $RC -eq 0 ]'
check "no se crea ~/.zshenv" '[ ! -e "$H/.zshenv" ] && [ ! -L "$H/.zshenv" ]'
check "sí enlaza el resto (.zshrc es enlace al repo)" '[ -L "$H/.zshrc" ]'
check "informa [OMITIDO]" 'echo "$OUT" | strip | grep -q "OMITIDO"'

echo "== Z2/Z4 --links-only con ~/.zshenv propio (2 corridas)"
newhome; H="$T/home"; B="$T/respaldos"; echo "$OWN" > "$H/.zshenv"
for i in 1 2; do
  run "$H" "$B" "$INSTALL" --links-only
  check "corrida $i: rc=0" '[ $RC -eq 0 ]'
  check "corrida $i: ~/.zshenv sigue siendo el archivo propio, intacto" '[ ! -L "$H/.zshenv" ] && [ "$(cat "$H/.zshenv")" = "$OWN" ]'
  check "corrida $i: sin enlaces rotos" '[ "$(broken_links "$H")" = 0 ]'
done
check "no se creó ningún respaldo (no hizo falta)" '[ ! -d "$B" ]'

echo "== Z2/Z4 --dry-run con ~/.zshenv propio (2 corridas)"
newhome; H="$T/home"; B="$T/respaldos"; echo "$OWN" > "$H/.zshenv"
for i in 1 2; do
  run "$H" "$B" "$INSTALL" --dry-run
  check "corrida $i: rc=0" '[ $RC -eq 0 ]'
  check "corrida $i: ~/.zshenv intacto" '[ ! -L "$H/.zshenv" ] && [ "$(cat "$H/.zshenv")" = "$OWN" ]'
done
check "dry-run no creó enlaces ni respaldos" '[ ! -d "$B" ] && [ "$(find "$H" -type l | grep -v /go/ | wc -l | tr -d " ")" = 0 ]'

echo "== Z3: check-links.sh sin --fix, estado real"
newhome; H="$T/home"; B="$T/respaldos"; echo "$OWN" > "$H/.zshenv"
run "$H" "$B" "$LINKS"
check "archivo propio: rc=1 (drift)" '[ $RC -eq 1 ]'
check "archivo propio: se reporta DRIFT y no SYMLINK OK" 'echo "$OUT" | strip | grep -q "DRIFT.*\.zshenv" && ! echo "$OUT" | strip | grep -qE "SYMLINK OK.*\.zshenv"'
check "archivo propio: sigue intacto tras solo verificar" '[ "$(cat "$H/.zshenv")" = "$OWN" ] && [ ! -d "$B" ]'
rm "$H/.zshenv"; mkdir -p "$T/otro"; echo "# otro" > "$T/otro/zshenv"; ln -s "$T/otro/zshenv" "$H/.zshenv"
run "$H" "$B" "$LINKS"
check "enlace a OTRO archivo llamado zshenv: rc=1" '[ $RC -eq 1 ]'
check "enlace a otro archivo: se reporta LINK EXTRAÑO, no OK" 'echo "$OUT" | strip | grep -q "LINK EXTRAÑO.*\.zshenv"'
check "con --no-zshenv y archivo propio: se omite y rc no lo cuenta" 'rm "$H/.zshenv"; echo "$OWN" > "$H/.zshenv"; run "$H" "$B" "$LINKS" --no-zshenv; echo "$OUT" | strip | grep -q "OMITIDO.*zshenv"'

echo "== Z2/Z4 modo completo (check-links --fix, lo que install.sh corre en el paso 6) con ~/.zshenv propio"
newhome; H="$T/home"; B="$T/respaldos"; echo "$OWN" > "$H/.zshenv"
run "$H" "$B" "$LINKS" --fix
check "corrida 1: rc=0" '[ $RC -eq 0 ]'
check "~/.zshenv ahora es el enlace al repo" '[ -L "$H/.zshenv" ] && [ "$(python3 -c "import os,sys;print(os.path.realpath(sys.argv[1]))" "$H/.zshenv")" = "$(python3 -c "import os,sys;print(os.path.realpath(sys.argv[1]))" "$ROOT/mac/zshenv")" ]'
check "el contenido propio quedó respaldado, byte a byte" 'f="$(find "$B" -name .zshenv | head -1)"; [ -n "$f" ] && [ "$(cat "$f")" = "$OWN" ]'
check "se avisó del respaldo" 'echo "$OUT" | strip | grep -q "RESPALDO.*\.zshenv"'
run "$H" "$B" "$LINKS" --fix
check "corrida 2: rc=0, idempotente" '[ $RC -eq 0 ]'
check "corrida 2: no creó otro respaldo" '[ "$(find "$B" -name .zshenv | wc -l | tr -d " ")" = 1 ]'
check "sin enlaces rotos" '[ "$(broken_links "$H")" = 0 ]'
run "$H" "$B" "$LINKS"
check "verificación posterior: rc=0 y .zshenv OK" '[ $RC -eq 0 ] && echo "$OUT" | strip | grep -q "SYMLINK OK.*\.zshenv"'

echo "== Z2: enlace extraño previo se respalda al arreglar"
newhome; H="$T/home"; B="$T/respaldos"; mkdir -p "$T/otro"; echo "# otro" > "$T/otro/zshenv"; ln -s "$T/otro/zshenv" "$H/.zshenv"
run "$H" "$B" "$LINKS" --fix
check "rc=0 y el enlace viejo quedó en respaldos" '[ $RC -eq 0 ] && [ -L "$(find "$B" -name .zshenv | head -1)" ] && [ -f "$T/otro/zshenv" ]'

echo "== Z2: dos respaldos en el mismo segundo no se pisan"
newhome; H="$T/home"; B="$T/respaldos"; export DOTFILES_BACKUP_STAMP=fijo
echo "primero" > "$H/.zshenv"; run "$H" "$B" "$LINKS" --fix
rm "$H/.zshenv"; echo "segundo" > "$H/.zshenv"; run "$H" "$B" "$LINKS" --fix
unset DOTFILES_BACKUP_STAMP
check "rc=0 y existen los dos respaldos con su contenido" '[ $RC -eq 0 ] && [ "$(cat "$B/fijo/.zshenv")" = primero ] && [ "$(cat "$B/fijo/.zshenv.1")" = segundo ]'

echo "== Hallazgos de Apoyo (reproducidos antes de corregir)"
newhome; H="$T/home"; B="$T/respaldos"
run "$H" "$B" "$LINKS"
check "faltantes: no se anuncia 'verificado con éxito' (rc 0 por compatibilidad)" '[ $RC -eq 0 ] && ! echo "$OUT" | strip | grep -q "verificado con éxito" && echo "$OUT" | strip | grep -q "faltan 14 enlaces"'
run "$H" "$B" "$LINKS" --strict
check "faltantes con --strict: rc=1" '[ $RC -eq 1 ]'
newhome; H="$T/home"; B="$T/respaldos"; ln -s /etc/passwd "$H/.zshenv"; mkdir -p "$T/bin"; printf '#!/bin/sh\nexit 1\n' > "$T/bin/python3"; chmod +x "$T/bin/python3"
OUT="$(HOME="$H" PATH="$T/bin:$PATH" DOTFILES_BACKUP_DIR="$B" "$LINKS" 2>&1)"; RC=$?
check "python3 roto: nunca un falso SYMLINK OK" '! echo "$OUT" | strip | grep -q "SYMLINK OK.*\.zshenv"'
newhome; H="$T/home"; B="$T/respaldos"; mkdir -p "$H/mis"; echo 'export A=1' > "$H/mis/zshenv"; (cd "$H" && ln -s mis/zshenv .zshenv)
run "$H" "$B" "$LINKS" --fix; f="$(find "$B" -name .zshenv | head -1)"
check "symlink relativo propio: el respaldo sigue resolviendo a su archivo" '[ $RC -eq 0 ] && [ -L "$f" ] && [ "$(cat "$f")" = "export A=1" ]'
newhome; H="$T/home"; B="$T/respaldos"; echo t > "$H/.zshenv"; mkdir -p "$B/fijo/.zshenv"
DOTFILES_BACKUP_STAMP=fijo run "$H" "$B" "$LINKS" --fix
check "directorio ya existente en el destino: no se anida, sufijo .1" '[ -f "$B/fijo/.zshenv.1" ] && [ -d "$B/fijo/.zshenv" ]'

echo "== Z5: PATH no interactivo con el enlace a mac/zshenv"
newhome; H="$T/home"; ln -s "$ROOT/mac/zshenv" "$H/.zshenv"
count() { tr ':' '\n' | grep -c "^$H/.local/bin$"; }
check "env -i zsh -c: \$HOME/.local/bin aparece exactamente 1 vez" '[ "$(env -i HOME="$H" zsh -c '"'"'echo $PATH'"'"' | count)" = 1 ]'
check "tras source dos veces sigue siendo 1" '[ "$(env -i HOME="$H" zsh -c '"'"'source ~/.zshenv; source ~/.zshenv; echo $PATH'"'"' | count)" = 1 ]'
check "con .local/bin ya en el PATH de entrada tampoco se duplica" '[ "$(env -i HOME="$H" PATH="$H/.local/bin:/usr/bin:/bin" zsh -c '"'"'echo $PATH'"'"' | count)" = 1 ]'
ZSHRC_LINE="$(grep -m1 '^export PATH="\$HOME/.local/bin' "$ROOT/mac/zshrc")"
check "zshrc usa su propia línea de PATH (el test depende de ella)" '[ -n "$ZSHRC_LINE" ]'
check "tras la línea REAL de mac/zshrc sigue siendo 1 (y queda al inicio)" 'p="$(env -i HOME="$H" ZL="$ZSHRC_LINE" zsh -c '"'"'source ~/.zshenv; eval "$ZL"; echo $PATH'"'"')"; [ "$(echo "$p" | count)" = 1 ] && [ "${p%%:*}" = "$H/.local/bin" ]'
check "se conserva lo anterior (rustup, cargo, brew)" 'p="$(env -i HOME="$H" zsh -c '"'"'echo $PATH'"'"')"; case "$p" in /opt/homebrew/opt/rustup/bin:*) true ;; *) false ;; esac; echo "$p" | grep -q "$H/.cargo/bin" && echo "$p" | grep -q "/opt/homebrew/bin"'

echo
if [ "$fails" -eq 0 ]; then echo "test-zshenv: PASS"; else echo "test-zshenv: $fails FAIL" >&2; fi
exit "$fails"
