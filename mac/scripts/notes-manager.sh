#!/usr/bin/env bash
# ==============================================================================
# notes-manager.sh — Gestor interactivo de notas en Markdown para herdr
# Stack: fzf (TUI) + glow (Catppuccin preview) + micro (Editor)
# Cero secuencias OSC incompatibles, 100% portable y local.
# ==============================================================================
set -euo pipefail

NOTES_DIR="${NOTES_DIR:-$HOME/Documents/notes}"
mkdir -p "$NOTES_DIR"

# Si el directorio está vacío, crear nota de bienvenida / cheatsheet
if [ -z "$(ls -A "$NOTES_DIR" 2>/dev/null)" ]; then
  cat <<'EOF' > "$NOTES_DIR/00-Bienvenida.md"
# 📓 Notas Rápidas — Mathias

Bienvenido a tu gestor de notas integrado en **herdr**.

## Atajos del Gestor:
- **Enter:** Abrir y editar la nota seleccionada en `micro`
- **Ctrl+N:** Crear una nueva nota (con nombre personalizado o fecha)
- **Ctrl+D:** Eliminar la nota seleccionada (pide confirmación)
- **Esc / Ctrl+C:** Cerrar el popup de notas

## Consejos de Markdown en micro:
- Usa `Ctrl+S` para guardar en `micro`
- Usa `Ctrl+Q` para salir de `micro` y volver al buscador
- Las notas se guardan en: `~/Documents/notes`
EOF
fi

# Colores Catppuccin Mocha para fzf
FZF_CATPPUCCIN="--color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 \
--color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
--color=marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8"

commit_notes() {
  if [ -d "$NOTES_DIR/.git" ]; then
    (
      cd "$NOTES_DIR"
      git add -A
      git diff --cached --quiet || git commit -m "Auto-sync notes: $(date '+%Y-%m-%d %H:%M')" --quiet || true
    )
  fi
}

create_note() {
  local prompt_name=""
  echo -ne "\033[38;2;203;166;247m\033[1mNombre de la nueva nota (o Enter para fecha de hoy): \033[0m"
  read -r prompt_name

  local filename=""
  if [ -z "$prompt_name" ]; then
    filename="$(date '+%Y-%m-%d_%H%M').md"
  else
    # Reemplazar espacios por guiones si los hay
    local clean_name
    clean_name="$(echo "$prompt_name" | tr ' ' '_')"
    if [[ "$clean_name" != *.md ]]; then
      filename="${clean_name}.md"
    else
      filename="$clean_name"
    fi
  fi

  local target="$NOTES_DIR/$filename"
  if [ ! -f "$target" ]; then
    cat <<EOF > "$target"
# ${prompt_name:-Nota $(date '+%Y-%m-%d')}

Creada: $(date '+%Y-%m-%d %H:%M')

EOF
  fi

  micro "$target"
  commit_notes
}

delete_note() {
  local note_name="$1"
  if [ -z "$note_name" ]; then
    return
  fi
  echo -ne "\033[38;2;243;139;168m\033[1m¿Eliminar '$note_name'? (s/N): \033[0m"
  read -r confirm
  if [[ "$confirm" =~ ^[sSyY]$ ]]; then
    rm -f "$NOTES_DIR/$note_name"
    commit_notes
    echo -e "\033[38;2;166;227;161mNota eliminada.\033[0m"
    sleep 0.5
  fi
}

main_loop() {
  while true; do
    local files
    files="$(cd "$NOTES_DIR" && ls -1t *.md 2>/dev/null || true)"

    if [ -z "$files" ]; then
      echo -e "\033[38;2;249;226;175mNo hay notas aún en $NOTES_DIR.\033[0m"
      create_note
      continue
    fi

    # fzf con preview en vivo usando glow
    local selection
    selection=$(
      echo "$files" | fzf \
        $FZF_CATPPUCCIN \
        --height="100%" \
        --layout=reverse \
        --border=rounded \
        --prompt=" 󰠮 Notas ❯ " \
        --header="[Enter] Editar | [Ctrl+N] Nueva Nota | [Ctrl+D] Borrar | [Esc] Salir" \
        --expect="ctrl-n,ctrl-d" \
        --preview="glow -s dark -w 70 \"$NOTES_DIR/{}\" 2>/dev/null || cat \"$NOTES_DIR/{}\"" \
        --preview-window="right:62%:wrap"
    ) || break

    local key
    local selected_file
    key=$(echo "$selection" | head -n 1)
    selected_file=$(echo "$selection" | tail -n +2 | head -n 1)

    case "$key" in
      ctrl-n)
        create_note
        ;;
      ctrl-d)
        if [ -n "$selected_file" ]; then
          delete_note "$selected_file"
        fi
        ;;
      *)
        if [ -n "$selected_file" ]; then
          micro "$NOTES_DIR/$selected_file"
          commit_notes
        fi
        ;;
    esac
  done
}

main_loop
