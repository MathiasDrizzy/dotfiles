#!/usr/bin/env bash
# ==============================================================================
# terminal-popup.sh — Terminal Scratchpad flotante para herdr (herdr key: prefix+t)
# Una zsh interactiva dentro de tmux. Se cierra con:
# - [Esc] (si la línea de comando está vacía)
# - [Ctrl+Q]
# - [Ctrl+D]
# - o escribiendo 'exit'
# Copiar: arrastra con el mouse (doble clic: palabra, triple: línea) y queda en el portapapeles.
# Pegar: Cmd+V, o Ctrl+V. Ctrl+Y copia la línea que escribes.
# tmux está solo para el mouse: un popup de herdr solo le pasa el mouse al programa que lo pide.
# ==============================================================================
set -euo pipefail

export HERDR_POPUP=1

self="${BASH_SOURCE[0]}"
if [ -L "$self" ]; then
  target="$(/usr/bin/readlink "$self")"
  case "$target" in
  /*) self="$target" ;;
  *) self="$(dirname "$self")/$target" ;;
  esac
fi
conf="$(cd "$(dirname "$self")/../config/tmux" && pwd)/scratchpad.conf"
banner='\033[38;2;203;166;247m\033[1m⚡ scratchpad\033[0m  \033[2m·  esc cerrar  ·  arrastra para copiar  ·  cmd+v pegar\033[0m\n'

# Without tmux (or without its config) the popup is a plain shell: nothing else of the scratchpad depends on it.
if command -v tmux >/dev/null 2>&1 && [ -f "$conf" ]; then
  exec tmux -L herdr-scratchpad -f "$conf" new-session "printf '%b' '$banner'; exec /bin/zsh -l"
fi
printf '%b' "$banner"
exec /bin/zsh -l
