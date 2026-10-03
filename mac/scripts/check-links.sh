#!/usr/bin/env bash
# ==============================================================================
# check-links.sh — Verificador y Sincronizador de Enlaces Simbólicos de Dotfiles
# Verifica si ~/.config/... coincide con ~/dotfiles/mac/config/...
# Detecta si se editó algún archivo fuera del repositorio git y previene pérdida de cambios.
# Uso:
#   mac/scripts/check-links.sh         # Solo verificar y reportar
#   mac/scripts/check-links.sh --fix   # Crear/reparar symlinks con backup automático
#   mac/scripts/check-links.sh --strict   # además, enlaces faltantes => exit 1
#   mac/scripts/check-links.sh --fix --no-zshenv   # igual, pero sin gestionar ~/.zshenv (lo usa install.sh --links-only)
# Nunca se pierde un archivo propio: antes de reemplazarlo se mueve a .respaldos/<fecha>/ del repo
# (ignorado por git; se puede cambiar con DOTFILES_BACKUP_DIR) y se avisa.
# ==============================================================================
set -euo pipefail

# Colores Catppuccin Mocha
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_MAUVE="\033[38;2;203;166;247m"
C_BLUE="\033[38;2;137;180;250m"
C_GREEN="\033[38;2;166;227;161m"
C_RED="\033[38;2;243;139;168m"
C_YELLOW="\033[38;2;249;226;175m"
C_SUBTEXT="\033[38;2;166;173;200m"

# Directorio del repositorio de dotfiles
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

REPO_ROOT="$(cd "$DOTFILES_DIR/.." && pwd)"
BACKUP_ROOT="${DOTFILES_BACKUP_DIR:-$REPO_ROOT/.respaldos}"
BACKUP_STAMP="${DOTFILES_BACKUP_STAMP:-$(date +%Y%m%d-%H%M%S)}"

FIX_MODE=false
NO_ZSHENV=false
STRICT=false
for arg in "$@"; do
  case "$arg" in
    --fix|--sync) FIX_MODE=true ;;
    --no-zshenv) NO_ZSHENV=true ;;
    --strict) STRICT=true ;;
  esac
done

# Mueve un archivo o enlace propio a .respaldos/ antes de reemplazarlo y avisa dónde quedó.
backup_target() {
  local target="$1" rel dest
  rel="${target#"$HOME"/}"
  dest="$BACKUP_ROOT/$BACKUP_STAMP/$rel"
  mkdir -p "$(dirname "$dest")"
  # Nunca pisar un respaldo anterior (dos corridas en el mismo segundo): sufijo .1, .2…
  local base="$dest" n=1
  while [ -e "$dest" ] || [ -L "$dest" ]; do dest="$base.$n"; n=$((n + 1)); done
  if [ -L "$target" ]; then
    # Un enlace relativo movido de carpeta se rompería: el respaldo apunta al destino absoluto original.
    abs="$(python3 -c 'import os,sys; t=sys.argv[1]; print(os.path.normpath(os.path.join(os.path.dirname(t), os.readlink(t))))' "$target")"
    ln -s "$abs" "$dest" && rm "$target"
  else
    mv "$target" "$dest"
  fi
  echo -e "      ↳ ${C_YELLOW}[RESPALDO]${C_RESET} tu $target se guardó en $dest"
}

# Ruta real (sin enlaces) de un archivo. Sin python3 no se puede comparar rutas de forma fiable
# (una cadena vacía igualaría a otra vacía y daría un falso OK), así que se aborta.
command -v python3 >/dev/null 2>&1 || { echo "check-links.sh necesita python3" >&2; exit 2; }
real_path() {
  python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"
}

echo -e "${C_BOLD}${C_MAUVE}═══════════════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_BOLD}${C_MAUVE}       DOTFILES LINK CHECKER & DRIFT DETECTOR${C_RESET}"
echo -e "${C_BOLD}${C_MAUVE}═══════════════════════════════════════════════════════════════${C_RESET}"
echo -e "Repositorio: ${C_BLUE}$DOTFILES_DIR${C_RESET}"
if [ "$FIX_MODE" = true ]; then
  echo -e "Modo: ${C_YELLOW}--fix activo (sincronizando y enlazando)${C_RESET}"
fi
echo ""

# Pares de archivos: "ARCHIVO_REPO | ARCHIVO_DESTINO"
CONFIG_PAIRS=(
  "config/ghostty/config|$HOME/.config/ghostty/config"
  "config/herdr/config.toml|$HOME/.config/herdr/config.toml"
  "config/yazi/keymap.toml|$HOME/.config/yazi/keymap.toml"
  "config/yazi/theme.toml|$HOME/.config/yazi/theme.toml"
  "config/micro/settings.json|$HOME/.config/micro/settings.json"
  "config/termscp/config.toml|$HOME/.config/termscp/config.toml"
  "config/termscp/theme.toml|$HOME/.config/termscp/theme.toml"
  "config/btop/btop.conf|$HOME/.config/btop/btop.conf"
  "config/bat/config|$HOME/.config/bat/config"
  "config/lazygit/config.yml|$HOME/Library/Application Support/lazygit/config.yml"
  "config/lazydocker/config.yml|$HOME/Library/Application Support/lazydocker/config.yml"
  "zshrc|$HOME/.zshrc"
  "zshenv|$HOME/.zshenv"
  "scripts/terminal-popup.sh|$HOME/.local/bin/terminal-popup"
)

drifts=0
symlinks_ok=0
copies_in_sync=0
missing=0

for pair in "${CONFIG_PAIRS[@]}"; do
  repo_rel="${pair%%|*}"
  target="${pair##*|}"
  source="$DOTFILES_DIR/$repo_rel"

  if [ ! -e "$source" ]; then
    echo -e "  ${C_RED}[ALERTA]${C_RESET} Fuente inexistente en repo: $repo_rel"
    continue
  fi

  if [ "$NO_ZSHENV" = true ] && [ "$repo_rel" = "zshenv" ]; then
    if [ -e "$target" ] || [ -L "$target" ]; then
      echo -e "  ${C_BLUE}[OMITIDO]${C_RESET} $target existe y se deja intacto (--no-zshenv)"
    else
      echo -e "  ${C_BLUE}[OMITIDO]${C_RESET} $target no se gestiona con --no-zshenv"
    fi
    continue
  fi

  if [ ! -e "$target" ] && [ ! -L "$target" ]; then
    if [ "$FIX_MODE" = true ]; then
      mkdir -p "$(dirname "$target")"
      ln -s "$source" "$target"
      echo -e "  ${C_GREEN}[ENLAZADO]${C_RESET} Creado symlink para $target"
      symlinks_ok=$((symlinks_ok + 1))
    else
      echo -e "  ${C_YELLOW}[MISSING]${C_RESET} $target no existe en el sistema"
      missing=$((missing + 1))
    fi
    continue
  fi

  if [ -L "$target" ]; then
    link_dest="$(readlink "$target")"
    # Comparar rutas reales: un enlace a otro archivo que se llame igual NO es el del repo.
    real_target="$(real_path "$target")"; real_source="$(real_path "$source")"
    if [ -n "$real_target" ] && [ "$real_target" = "$real_source" ]; then
      echo -e "  ${C_GREEN}[SYMLINK OK]${C_RESET} $target"
      symlinks_ok=$((symlinks_ok + 1))
    else
      echo -e "  ${C_YELLOW}[LINK EXTRAÑO]${C_RESET} $target apunta a $link_dest"
      drifts=$((drifts + 1))
      if [ "$FIX_MODE" = true ]; then
        backup_target "$target"
        ln -s "$source" "$target"
        echo -e "      ↳ ${C_GREEN}Enlazado hacia el repo${C_RESET}"
      fi
    fi
  else
    # Es un archivo regular, comparar contenidos
    if cmp -s "$source" "$target"; then
      if [ "$FIX_MODE" = true ]; then
        ln -sf "$source" "$target"
        echo -e "  ${C_GREEN}[CONVERTIDO A SYMLINK]${C_RESET} $target"
        symlinks_ok=$((symlinks_ok + 1))
      else
        echo -e "  ${C_BLUE}[IN SYNC (Copia)]${C_RESET} $target (idéntico al repo)"
        copies_in_sync=$((copies_in_sync + 1))
      fi
    else
      echo -e "  ${C_RED}[DRIFT / MODIFICADO FUERA DE GIT]${C_RESET} $target"
      echo -e "      ${C_SUBTEXT}El archivo en ~/.config difiere del repositorio:${C_RESET}"
      diff -u "$source" "$target" | head -n 12 || true
      drifts=$((drifts + 1))

      if [ "$FIX_MODE" = true ]; then
        backup_target "$target"
        ln -s "$source" "$target"
        echo -e "      ↳ ${C_GREEN}Enlazado hacia el repo${C_RESET}"
      fi
    fi
  fi
done

echo ""
echo -e "${C_BOLD}${C_MAUVE}───────────────────────────────────────────────────────────────${C_RESET}"
echo -e "Resultado: ${C_GREEN}$symlinks_ok Symlinks OK${C_RESET} | ${C_BLUE}$copies_in_sync Copias Sincronizadas${C_RESET} | ${C_RED}$drifts Modificaciones Fuera de Git${C_RESET} | ${C_YELLOW}$missing Faltantes${C_RESET}"
echo -e "${C_BOLD}${C_MAUVE}───────────────────────────────────────────────────────────────${C_RESET}"

if [ "$drifts" -gt 0 ] && [ "$FIX_MODE" = false ]; then
  echo -e "\n${C_RED}${C_BOLD}⚠️  ATENCIÓN:${C_RESET} Hay archivos modificados en ~/.config fuera de git."
  echo -e "Ejecuta '${C_BLUE}mac/scripts/check-links.sh --fix${C_RESET}' para sincronizar con backups automáticos."
  exit 1
fi

if [ "$missing" -gt 0 ]; then
  echo -e "\n${C_YELLOW}⚠ Sin discrepancias, pero faltan $missing enlaces. '${C_BLUE}check-links.sh --fix${C_YELLOW}' los crea.${C_RESET}"
  [ "$STRICT" = true ] && exit 1
  exit 0
fi

echo -e "\n${C_GREEN}✓ Estado de enlaces de dotfiles verificado con éxito.${C_RESET}"
exit 0
