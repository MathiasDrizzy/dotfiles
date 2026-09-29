#!/usr/bin/env bash
# ==============================================================================
# check-links.sh — Verificador y Sincronizador de Enlaces Simbólicos de Dotfiles
# Verifica si ~/.config/... coincide con ~/dotfiles/mac/config/...
# Detecta si se editó algún archivo fuera del repositorio git y previene pérdida de cambios.
# Uso:
#   mac/scripts/check-links.sh         # Solo verificar y reportar
#   mac/scripts/check-links.sh --fix   # Crear/reparar symlinks con backup automático
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

FIX_MODE=false
for arg in "$@"; do
  if [[ "$arg" == "--fix" || "$arg" == "--sync" ]]; then
    FIX_MODE=true
  fi
done

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
  "scripts/notes-manager.sh|$HOME/.local/bin/notes-manager"
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

  if [ ! -e "$target" ] && [ ! -L "$target" ]; then
    if [ "$FIX_MODE" = true ]; then
      mkdir -p "$(dirname "$target")"
      ln -s "$source" "$target"
      echo -e "  ${C_GREEN}[ENLAZADO]${C_RESET} Creado symlink para $target"
      ((symlinks_ok++))
    else
      echo -e "  ${C_YELLOW}[MISSING]${C_RESET} $target no existe en el sistema"
      ((missing++))
    fi
    continue
  fi

  if [ -L "$target" ]; then
    link_dest="$(readlink "$target")"
    # Resolver path canónico
    canonical_source="$(cd "$(dirname "$source")" && pwd)/$(basename "$source")"
    canonical_target_dir="$(cd "$(dirname "$target")" && pwd)"
    
    # Comprobar si el link apunta al repo
    if [[ "$link_dest" == "$source" || "$link_dest" == "$canonical_source" || "$link_dest" == *"$repo_rel"* ]]; then
      echo -e "  ${C_GREEN}[SYMLINK OK]${C_RESET} $target"
      ((symlinks_ok++))
    else
      echo -e "  ${C_YELLOW}[LINK EXTRAÑO]${C_RESET} $target apunta a $link_dest"
      if [ "$FIX_MODE" = true ]; then
        ln -sf "$source" "$target"
        echo -e "      ↳ ${C_GREEN}Corregido hacia repo local${C_RESET}"
      fi
    fi
  else
    # Es un archivo regular, comparar contenidos
    if cmp -s "$source" "$target"; then
      if [ "$FIX_MODE" = true ]; then
        ln -sf "$source" "$target"
        echo -e "  ${C_GREEN}[CONVERTIDO A SYMLINK]${C_RESET} $target"
        ((symlinks_ok++))
      else
        echo -e "  ${C_BLUE}[IN SYNC (Copia)]${C_RESET} $target (idéntico al repo)"
        ((copies_in_sync++))
      fi
    else
      echo -e "  ${C_RED}[DRIFT / MODIFICADO FUERA DE GIT]${C_RESET} $target"
      echo -e "      ${C_SUBTEXT}El archivo en ~/.config difiere del repositorio:${C_RESET}"
      diff -u "$source" "$target" | head -n 12 || true
      ((drifts++))

      if [ "$FIX_MODE" = true ]; then
        backup="${target}.bak.$(date +%s)"
        mv "$target" "$backup"
        ln -s "$source" "$target"
        echo -e "      ↳ ${C_YELLOW}Copia de seguridad guardada en $backup y enlazado a repo${C_RESET}"
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

echo -e "\n${C_GREEN}✓ Estado de enlaces de dotfiles verificado con éxito.${C_RESET}"
exit 0
