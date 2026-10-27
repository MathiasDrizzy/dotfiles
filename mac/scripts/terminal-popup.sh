#!/usr/bin/env bash
# ==============================================================================
# terminal-popup.sh — Terminal Scratchpad provisoria para herdr (pane temporal)
# Lanza una terminal zsh interactiva que se cierra con:
# - [Esc] (si la línea de comando está vacía)
# - [Ctrl+Q]
# - [Ctrl+D]
# - o escribiendo 'exit'
# ==============================================================================
set -euo pipefail

export HERDR_POPUP=1

# Una sola línea tenue: cómo se cierra. Sin lista de aliases: caduca y el prompt ya dice dónde estás.
printf '\033[38;2;203;166;247m\033[1m⚡ scratchpad\033[0m  \033[2m·  esc para cerrar\033[0m\n'

# Iniciar sesión zsh interactiva
exec /bin/zsh -l
