#!/usr/bin/env bash
# Prueba de punta a punta de `mac/install.sh` en modo completo, sin tocar el Mac real (ORD-dotfiles-005 D2).
#
# Aislamiento (varias capas, porque el modo completo instala paquetes):
#  1. HOME temporal; `env -i` con un PATH propio que empieza por stubs de brew, curl y rustup que solo REGISTRAN
#     sus llamadas. install.sh usa $DOTFILES_BREW_PREFIX en vez de /opt/homebrew para que el brew real no entre.
#  2. El test se niega a ejecutar nada si install.sh aún tiene rutas fijas de /opt/homebrew (pre-vuelo).
#  3. `sandbox-exec` prohíbe ESCRIBIR en /opt/homebrew y en lo que cuelga del HOME real (salvo la caché de Go).
#     Si algo se escapara, el sistema lo corta y el test lo cuenta como fallo.
# La copia del repo se hace desde el árbol de trabajo (incluye cambios sin commit) y NO es el repo real.
#
# Comprueba: I1 (2 corridas: rc=0, idempotente, sin enlaces rotos, llamadas a brew registradas) e I2 (HOME y repo con espacios),
# más un ~/.zshenv propio previo (se respalda, nunca se pierde).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_HOME="$HOME"
fails=0; TMPS=()
ok()   { printf '  PASS  %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1  [$2]"; fi; }
cleanup() { for t in ${TMPS[@]+"${TMPS[@]}"}; do chmod -R u+w "$t" 2>/dev/null; rm -rf "$t"; done; }
trap cleanup EXIT

echo "== Pre-vuelo: ¿install.sh se puede aislar?"
if grep -nE '(^|[^_A-Za-z])/opt/homebrew' "$ROOT/mac/install.sh" | grep -v 'BREW_PREFIX:-/opt/homebrew' | grep -q .; then
  grep -nE '(^|[^_A-Za-z])/opt/homebrew' "$ROOT/mac/install.sh" | grep -v 'BREW_PREFIX:-/opt/homebrew'
  fail "install.sh tiene rutas fijas de /opt/homebrew: no se ejecuta nada (podría llamar al brew real)"
  echo; echo "test-install-full: $fails FAIL (no se ejecutó install.sh)" >&2; exit "$fails"
fi
ok "install.sh no tiene rutas fijas de /opt/homebrew fuera del valor por defecto de DOTFILES_BREW_PREFIX"
command -v sandbox-exec >/dev/null || { fail "falta sandbox-exec para la capa 3"; exit 1; }
REAL_BIN_SUM="$(shasum "$REAL_HOME/.local/bin/herdr-ctl" 2>/dev/null)"
REAL_ZSHENV_LINK="$(readlink "$REAL_HOME/.zshenv" 2>/dev/null)"
REAL_BREW_MTIME="$(stat -f %m /opt/homebrew/bin/brew 2>/dev/null)"
GO_REAL="$(command -v go)"; GOROOT_REAL="$(go env GOROOT)"
GOCACHE_REAL="$(go env GOCACHE)"; GOMODCACHE_REAL="$(go env GOMODCACHE)"; GOPATH_REAL="$(go env GOPATH)"

# scenario <nombre> <dir del HOME> <dir del repo> → deja $B (base temporal) listo con repo copiado y stubs
mkbase() {
  B="$(mktemp -d "${TMPDIR:-/tmp}/installfull.XXXXXX")"; TMPS+=("$B")
  mkdir -p "$B/stubs" "$B/brewprefix/bin" "$B/logs" "$B/respaldos" "$B/gobin"
  ln -s "$GO_REAL" "$B/gobin/go"      # solo `go`, NO su directorio (puede ser /opt/homebrew/bin, donde vive el brew real)
  # stubs: solo registran
  cat > "$B/stubs/brew" <<EOF
#!/usr/bin/env bash
echo "brew \$*" >> "$B/logs/brew.log"; echo "\$0" >> "$B/logs/brew.bin"
case "\$1" in --version) echo "Homebrew 0.0-stub" ;; list) exit 1 ;; shellenv) : ;; esac
exit 0
EOF
  cat > "$B/stubs/curl" <<EOF
#!/usr/bin/env bash
echo "curl \$*" >> "$B/logs/curl.log"
out=""; prev=""; for a in "\$@"; do [ "\$prev" = "-o" ] && out="\$a"; prev="\$a"; done
[ -n "\$out" ] && echo "# tema de prueba (stub)" > "\$out"
exit 0
EOF
  cat > "$B/stubs/rustup" <<EOF
#!/usr/bin/env bash
echo "rustup \$*" >> "$B/logs/rustup.log"; exit 0
EOF
  mv "$B/stubs/brew" "$B/brewprefix/bin/brew"; chmod +x "$B/stubs/"* "$B/brewprefix/bin/brew"
}
mkrepo() { # mkrepo <ruta destino>: copia del árbol de trabajo (versionado + sin versionar no ignorado) + git init
  local dest="$1"; mkdir -p "$dest"
  ( cd "$ROOT" && git ls-files -z --cached --others --exclude-standard | while IFS= read -r -d '' f; do [ -e "$f" ] && printf '%s\0' "$f"; done | tar --null -T - -cf - ) | tar -xf - -C "$dest"
  [ -f "$dest/mac/install.sh" ] || { echo "ERROR del test: la copia del repo salió vacía"; exit 2; }
  ( cd "$dest" && git init -q )
}
profile() { # perfil de sandbox: escritura prohibida en el Mac real
  cat <<EOF
(version 1)
(allow default)
(deny network*)
(deny file-write* (subpath "/opt/homebrew") (subpath "$REAL_HOME/.config") (subpath "$REAL_HOME/.local")
  (subpath "$REAL_HOME/Library/Application Support") (subpath "$REAL_HOME/Documents") (subpath "$REAL_HOME/.cargo")
  (literal "$REAL_HOME/.zshenv") (literal "$REAL_HOME/.zshrc"))
(allow file-write* (subpath "$GOCACHE_REAL") (subpath "$GOPATH_REAL/pkg/mod/cache"))
EOF
}
test_path() { printf '%s' "$B/stubs${BREW_ON_PATH:+:$B/brewprefix/bin}:$B/gobin:/usr/bin:/bin:/usr/sbin:/sbin"; }
run_install() {
  # Guarda de seguridad ANTES de ejecutar: el único brew/rustup alcanzable por el PATH debe ser el stub (o ninguno).
  local who
  for who in brew rustup; do
    p="$(PATH="$(test_path)" command -v "$who" 2>/dev/null)"
    case "$p" in ""|"$B"/*) ;; *) echo "ABORTO: '$who' resolvería a $p (real); no se ejecuta install.sh"; exit 3 ;; esac
  done # run_install <HOME> <repo> [args…]   (salida en $OUT, rc en $RC)
  local h="$1" repo="$2"; shift 2
  OUT="$(sandbox-exec -p "$(profile)" env -i HOME="$h" TMPDIR="$B/tmp" \
      PATH="$(test_path)" GOROOT="$GOROOT_REAL" \
      DOTFILES_BREW_PREFIX="$B/brewprefix" DOTFILES_BACKUP_DIR="$B/respaldos" \
      GOCACHE="$GOCACHE_REAL" GOMODCACHE="$GOMODCACHE_REAL" GOPATH="$GOPATH_REAL" \
      bash "$repo/mac/install.sh" "$@" 2>&1)"; RC=$?
}
strip() { sed 's/\x1b\[[0-9;]*m//g'; }
broken() { find "$1" -type l ! -exec test -e {} \; -print 2>/dev/null | grep -v '/go/' | wc -l | tr -d ' '; }
snapshot() { ( cd "$1" && find . -path ./go -prune -o \( -type l -print \) | sort | while read -r l; do printf '%s -> %s\n' "$l" "$(readlink "$l")"; done; ls -1A .config .local/bin 2>/dev/null ); }
expected_pkgs() { awk '/^BREW_PACKAGES=\(/{f=1;next} f&&/^\)/{exit} f{print}' "$ROOT/mac/install.sh" | tr -s ' \n' '\n' | grep -v '^$' | sort | tr '\n' ' '; }

scenario() { # scenario <titulo> <home con o sin espacios> <repo con o sin espacios> <zshenv propio: 0|1>
  local title="$1" hname="$2" rname="$3" own="$4" brewpath="${5:-1}"
  [ -z "${ONLY:-}" ] || [[ "$title" == "$ONLY"* ]] || return 0
  echo "== $title"
  BREW_ON_PATH=""; [ "$brewpath" = 1 ] && BREW_ON_PATH=1
  mkbase; mkdir -p "$B/tmp"
  local H="$B/$hname" REPO="$B/$rname"
  mkdir -p "$H"; mkrepo "$REPO"
  [ "$own" = 1 ] && echo 'export MI_VAR=propia  # contenido del usuario' > "$H/.zshenv"

  run_install "$H" "$REPO"
  check "corrida 1: rc=0" '[ $RC -eq 0 ]'
  [ $RC -ne 0 ] && echo "$OUT" | tail -15
  check "brew install registrado con TODOS los paquetes de BREW_PACKAGES" \
    'got="$(grep "^brew install " "$B/logs/brew.log" | grep -v -- "--cask" | head -1 | sed "s/^brew install //" | tr -s " " "\n" | sort | tr "\n" " ")"; [ "$got" = "$(expected_pkgs)" ]'
  check "brew install --cask de la fuente registrado" 'grep -q "^brew install --cask font-jetbrains-mono-nerd-font" "$B/logs/brew.log"'
  check "rustup default stable registrado" 'grep -q "^rustup default stable" "$B/logs/rustup.log"'
  check "se descargaron los 2 temas (curl stub)" '[ "$(grep -c "^curl " "$B/logs/curl.log")" = 2 ] && [ -f "$H/.config/micro/colorschemes/catppuccin-mocha.micro" ]'
  check "herdr-ctl compilado en ~/.local/bin" '[ -x "$H/.local/bin/herdr-ctl" ]'
  check "todos los enlaces de check-links.sh quedan OK (--strict: 0 faltantes, rc 0)" \
    'n="$(grep -c "^  \".*|\$HOME/" "$REPO/mac/scripts/check-links.sh")"; [ "$n" -ge 10 ]; o="$(HOME="$H" DOTFILES_BACKUP_DIR="$B/respaldos" "$REPO/mac/scripts/check-links.sh" --strict 2>&1 | strip)"; rc=$?; echo "$o" | grep -q " 0 Faltantes" && echo "$o" | grep -q "$n Symlinks OK" && echo "$o" | grep -q "0 Modificaciones Fuera de Git"'
  check "sin enlaces rotos" '[ "$(broken "$H")" = 0 ]'
  check "~/.zshenv es el enlace a mac/zshenv" '[ -L "$H/.zshenv" ] && [ "$(python3 -c "import os,sys;print(os.path.realpath(sys.argv[1]))" "$H/.zshenv")" = "$(python3 -c "import os,sys;print(os.path.realpath(sys.argv[1]))" "$REPO/mac/zshenv")" ]'
  check "core.hooksPath quedó en la copia del repo, no en el real" '[ "$(git -C "$REPO" config --get core.hooksPath)" = "scripts/hooks" ]'
  if [ "$own" = 1 ]; then
    check "el ~/.zshenv propio quedó respaldado byte a byte y avisado" 'f="$(find "$B/respaldos" -name .zshenv | head -1)"; [ -n "$f" ] && [ "$(cat "$f")" = "export MI_VAR=propia  # contenido del usuario" ] && echo "$OUT" | strip | grep -q "RESPALDO"'
  else
    check "no se creó ningún respaldo" '[ -z "$(find "$B/respaldos" -type f)" ]'
  fi

  snap1="$(snapshot "$H")"; calls1="$(cat "$B/logs/brew.log")"; nresp1="$(find "$B/respaldos" -type f | wc -l | tr -d ' ')"
  run_install "$H" "$REPO"
  check "corrida 2: rc=0" '[ $RC -eq 0 ]'
  check "corrida 2 idempotente: mismos enlaces y archivos" '[ "$(snapshot "$H")" = "$snap1" ]'
  check "corrida 2: sin más respaldos" '[ "$(find "$B/respaldos" -type f | wc -l | tr -d " ")" = "$nresp1" ]'
  check "corrida 2: mismas llamadas a brew que la 1 (registradas dos veces)" '[ "$(cat "$B/logs/brew.log")" = "$(printf "%s\n%s" "$calls1" "$calls1")" ]'
  check "corrida 2: sin enlaces rotos" '[ "$(broken "$H")" = 0 ]'
  [ "$brewpath" = 1 ] || check "no intentó reinstalar Homebrew (no hubo curl a Homebrew/install) y sí usó el brew del prefijo" '! grep -q "Homebrew/install" "$B/logs/curl.log" && grep -q "^brew install " "$B/logs/brew.log"'
  check "la sandbox no reportó escrituras denegadas" '! echo "$OUT" | grep -qi "operation not permitted"'
  check "todo brew invocado fue el stub de la prueba (ruta registrada por el propio stub)" '[ -s "$B/logs/brew.bin" ] && ! grep -v "^$B/" "$B/logs/brew.bin" | grep -q .'
}

scenario "I1: HOME limpio, dos corridas"                 "home"             "repo"              0
scenario "I1b: HOME con un ~/.zshenv propio"             "home"             "repo"              1
scenario "I3: Homebrew ya instalado en su prefijo pero fuera del PATH" "home" "repo" 0 0
scenario "I2: HOME y repo con espacios"                  "home con espacios" "repo con espacios" 0
scenario "I2b: HOME con espacios y ~/.zshenv propio"     "home con espacios" "repo con espacios" 1

echo "== Real intacto (sin escrituras fuera de la copia)"
check "canario: dentro de la sandbox NO se puede escribir en el HOME real" 'c="$REAL_HOME/.local/zz-canario-$$"; sandbox-exec -p "$(profile)" touch "$c" 2>/dev/null; rc=$?; r=0; [ -e "$c" ] && { r=1; rm -f "$c"; }; [ $rc -ne 0 ] && [ $r -eq 0 ]'
check "canario: dentro de la sandbox NO hay red" '! sandbox-exec -p "$(profile)" /usr/bin/curl -s -m 3 -o /dev/null https://example.com 2>/dev/null'
check "el herdr-ctl real no cambió (shasum igual que antes de la prueba)" '[ "$(shasum "$REAL_HOME/.local/bin/herdr-ctl" 2>/dev/null)" = "$REAL_BIN_SUM" ]'
check "el ~/.zshenv real apunta a lo mismo que antes" '[ "$(readlink "$REAL_HOME/.zshenv" 2>/dev/null)" = "$REAL_ZSHENV_LINK" ]'
check "el brew real no cambió (mtime igual que antes)" '[ "$(stat -f %m /opt/homebrew/bin/brew 2>/dev/null)" = "$REAL_BREW_MTIME" ]'

echo
if [ "$fails" -eq 0 ]; then echo "test-install-full: PASS"; else echo "test-install-full: $fails FAIL" >&2; fi
exit "$fails"
