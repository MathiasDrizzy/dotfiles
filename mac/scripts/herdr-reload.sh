#!/usr/bin/env bash
# ==============================================================================
# herdr-reload.sh — Recarga en caliente de configuración para herdr
# Comunica directamente con herdr.sock para aplicar cambios de config.toml
# sin tener que cerrar ni reiniciar la terminal Ghostty.
# ==============================================================================
set -euo pipefail

# Colores Catppuccin Mocha
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_MAUVE="\033[38;2;203;166;247m"
C_GREEN="\033[38;2;166;227;161m"
C_RED="\033[38;2;243;139;168m"
C_YELLOW="\033[38;2;249;226;175m"
C_BLUE="\033[38;2;137;180;250m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_CONFIG="$SCRIPT_DIR/../config/herdr/config.toml"
HERDR_DIR="$HOME/.config/herdr"
HERDR_CONFIG="$HERDR_DIR/config.toml"
HERDR_SOCK="$HERDR_DIR/herdr.sock"

# 1. Validar sintaxis TOML antes de aplicar nada
if ! python3 -c "import tomllib; tomllib.load(open('$REPO_CONFIG', 'rb'))" 2>/dev/null; then
  echo -e "${C_RED}[ERROR]${C_RESET} Sintaxis inválida en $REPO_CONFIG. Cancelando recarga."
  exit 1
fi

# 2. Sincronizar hacia ~/.config/herdr/config.toml si es archivo independiente
if [ -f "$HERDR_CONFIG" ] && [ ! -L "$HERDR_CONFIG" ]; then
  if ! cmp -s "$REPO_CONFIG" "$HERDR_CONFIG"; then
    cp "$REPO_CONFIG" "$HERDR_CONFIG"
    echo -e "${C_BLUE}[SYNC]${C_RESET} Sincronizado $REPO_CONFIG -> $HERDR_CONFIG"
  fi
elif [ ! -e "$HERDR_CONFIG" ]; then
  cp "$REPO_CONFIG" "$HERDR_CONFIG"
fi

# 3. Comprobar si herdr server está activo a través del socket
if [ ! -S "$HERDR_SOCK" ]; then
  echo -e "${C_YELLOW}[INFO]${C_RESET} Socket de herdr no encontrado en $HERDR_SOCK."
  echo -e "Los cambios se aplicarán automáticamente la próxima vez que inicies herdr."
  exit 0
fi

# 4. Enviar señal de recarga en caliente
echo -e "${C_MAUVE}[HERDR]${C_RESET} Enviando señal de recarga en caliente via socket..."
if command -v herdr &>/dev/null; then
  output="$(herdr server reload-config 2>&1)"
  if echo "$output" | grep -q '"status":"applied"'; then
    echo -e "${C_GREEN}[HERDR] ✓ Configuración recargada en caliente con éxito.${C_RESET}"
    exit 0
  else
    echo -e "${C_RED}[HERDR] ⚠️ Respuesta de recarga:${C_RESET} $output"
    exit 1
  fi
else
  echo -e "${C_RED}[ERROR]${C_RESET} Binario 'herdr' no encontrado en PATH."
  exit 1
fi
