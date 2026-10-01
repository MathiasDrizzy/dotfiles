#!/usr/bin/env bash
# ==============================================================================
# terminal-popup.sh — Terminal Scratchpad flotante para herdr
# Lanza una terminal zsh interactiva en popup que se cierra con:
# - [Esc] (si la línea de comando está vacía)
# - [Ctrl+Q]
# - [Ctrl+D]
# - o escribiendo 'exit'
# ==============================================================================
set -euo pipefail

export HERDR_POPUP=1

# Mostrar banner informativo sutil la primera vez
echo -e "\033[38;2;203;166;247m\033[1m⚡ Terminal Scratchpad\033[0m \033[38;2;166;173;200m· [Esc] o [Ctrl+D] para cerrar · aliases: sftp, hosts, lg, ld\033[0m\n"

# Iniciar sesión zsh interactiva
exec /bin/zsh -l
