#!/usr/bin/env bash
# ==============================================================================
# dotfiles/mac/install.sh
# Script automatizado e idempotente para configurar macOS (Apple Silicon)
# con Ghostty, herdr, Antigravity, zsh, Catppuccin Mocha y herramientas TUI.
# Soporta --dry-run (simulación) y --links-only (solo crea directorios y enlaces
# bajo $HOME; no instala paquetes, no descarga temas, no compila, no toca ~/.zshenv).
# ~/.zshenv es el enlace a mac/zshenv. Si ya existe uno propio, el modo completo lo respalda en
# .respaldos/ del repo antes de enlazar; --links-only ni lo toca.
# ==============================================================================
set -euo pipefail

DRY_RUN=false
LINKS_ONLY=false
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=true ;;
    --links-only) LINKS_ONLY=true ;;
  esac
done

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Prefijo de Homebrew. Solo se cambia para probar el instalador en aislamiento (scripts/test-install-full.sh).
BREW_PREFIX="${DOTFILES_BREW_PREFIX:-/opt/homebrew}"

if [ "$DRY_RUN" = true ]; then
  echo "════════════════════════════════════════════════════════════════"
  echo " [DRY-RUN] Simulando instalación de dotfiles (macOS)"
  echo "           No se realizarán modificaciones en el sistema"
  echo "════════════════════════════════════════════════════════════════"
else
  echo "==> Iniciando instalación de dotfiles (macOS)..."
  [ "$LINKS_ONLY" = true ] && echo "    (--links-only: solo directorios y enlaces bajo \$HOME)"
fi

# Helper para ejecución condicional
run_step() {
  local desc="$1"
  shift
  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY-RUN] $desc"
  else
    echo "==> $desc"
    "$@"
  fi
}

if [ "$LINKS_ONLY" = false ]; then

# 0. Homebrew ya instalado en su prefijo pero fuera del PATH de esta shell (p. ej. recién instalado): se usa tal cual
#    en vez de intentar reinstalarlo, y también en --dry-run (brew list) y en el resto del script.
if ! command -v brew &>/dev/null && [ -x "$BREW_PREFIX/bin/brew" ]; then
  export PATH="$BREW_PREFIX/bin:$PATH"
fi

# 1. Comprobar Homebrew
if ! command -v brew &>/dev/null; then
  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY-RUN] Homebrew no detectado. Se instalaría curl https://raw.githubusercontent.com/.../install.sh"
  else
    echo "==> Instalando Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$("$BREW_PREFIX/bin/brew" shellenv)"
  fi
else
  echo "  ✓ Homebrew disponible: $(brew --version | head -n 1)"
fi

# 2. PATH para el resto de este script (el archivo ~/.zshenv lo enlaza check-links.sh en el paso 6,
#    con respaldo si ya existía uno propio; aquí no se escribe nada en $HOME)
if [ "$DRY_RUN" = true ]; then
  echo "  [DRY-RUN] PATH de Homebrew + Rust + ~/.local/bin para esta ejecución"
else
  if [ -x "$BREW_PREFIX/bin/brew" ]; then
    eval "$("$BREW_PREFIX/bin/brew" shellenv)"
  fi
  export PATH="$BREW_PREFIX/opt/rustup/bin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
fi

# 3. Paquetes Homebrew esenciales
BREW_PACKAGES=(
  herdr ghostty micro glow bat git-delta go rustup
  yazi ffmpeg poppler fd ripgrep fzf zoxide atuin starship mise
  lazygit lazydocker termscp sshs btop chafa
  fzf-tab zsh-autosuggestions zsh-syntax-highlighting
)

if [ "$DRY_RUN" = true ]; then
  echo "  [DRY-RUN] Verificando lista de ${#BREW_PACKAGES[@]} paquetes Homebrew esenciales..."
  for pkg in "${BREW_PACKAGES[@]}"; do
    if brew list "$pkg" &>/dev/null; then
      echo "    ✓ Paquete instalado: $pkg"
    else
      echo "    ℹ Paquete pendiente de instalar: $pkg"
    fi
  done
else
  echo "==> Instalando fórmulas y casks de Homebrew..."
  brew install "${BREW_PACKAGES[@]}"
  brew install --cask font-jetbrains-mono-nerd-font || true
fi

# 4. Activar toolchain de Rust
if [ "$DRY_RUN" = true ]; then
  echo "  [DRY-RUN] Verificando toolchain de Rust (rustup default stable)"
else
  if command -v rustup &>/dev/null; then
    rustup default stable || true
  fi
fi

fi

# 5. Crear directorios de configuración
CONFIG_DIRS=(
  "$HOME/.config/ghostty"
  "$HOME/.config/herdr"
  "$HOME/.config/yazi"
  "$HOME/.config/micro/colorschemes"
  "$HOME/.config/btop/themes"
  "$HOME/.config/bat"
  "$HOME/.config/termscp"
  "$HOME/.local/bin"
  "$HOME/.local/share"
  "$HOME/.local/state"
  "$HOME/Documents/notes"
  "$HOME/Library/Application Support/lazygit"
  "$HOME/Library/Application Support/lazydocker"
)

if [ "$DRY_RUN" = true ]; then
  echo "  [DRY-RUN] Validando estructura de ${#CONFIG_DIRS[@]} directorios de configuración..."
else
  echo "==> Creando directorios..."
  for d in "${CONFIG_DIRS[@]}"; do
    mkdir -p "$d"
  done
fi

# 6. Validar / Enlazar configuraciones
echo "==> Verificando fuentes de configuración en $DOTFILES_DIR..."
REQUIRED_SOURCES=(
  "config/ghostty/config"
  "config/herdr/config.toml"
  "config/yazi/keymap.toml"
  "config/yazi/theme.toml"
  "config/micro/settings.json"
  "config/starship/starship.toml"
  "config/termscp/config.toml"
  "config/termscp/theme.toml"
  "config/lazygit/config.yml"
  "config/lazydocker/config.yml"
  "config/btop/btop.conf"
  "config/bat/config"
  "zshrc"
  "zshenv"
  "scripts/check-links.sh"
  "scripts/herdr-reload.sh"
  "scripts/terminal-popup.sh"
)

for src in "${REQUIRED_SOURCES[@]}"; do
  full_src="$DOTFILES_DIR/$src"
  if [ ! -f "$full_src" ]; then
    echo "❌ Error crítico: Fuente no encontrada: $full_src" >&2
    exit 1
  fi
done
echo "  ✓ ${#REQUIRED_SOURCES[@]} archivos fuente verificados correctamente."

if [ "$DRY_RUN" = true ]; then
  echo "  [DRY-RUN] Simulación de enlace de dotfiles via check-links.sh..."
  if [ "$LINKS_ONLY" = true ]; then
    "$DOTFILES_DIR/scripts/check-links.sh" --no-zshenv || true
  else
    "$DOTFILES_DIR/scripts/check-links.sh" || true
  fi
else
  echo "==> Sincronizando enlaces simbólicos..."
  if [ "$LINKS_ONLY" = true ]; then
    "$DOTFILES_DIR/scripts/check-links.sh" --fix --no-zshenv
  else
    "$DOTFILES_DIR/scripts/check-links.sh" --fix
  fi
fi

if [ "$LINKS_ONLY" = false ]; then

# 7. Tema Catppuccin Mocha para micro y btop
if [ "$DRY_RUN" = true ]; then
  echo "  [DRY-RUN] Validación de descargas de temas Catppuccin Mocha"
else
  curl -fsSL https://raw.githubusercontent.com/catppuccin/micro/main/themes/catppuccin-mocha.micro \
    -o "$HOME/.config/micro/colorschemes/catppuccin-mocha.micro" 2>/dev/null || true
  curl -fsSL https://raw.githubusercontent.com/catppuccin/btop/main/themes/catppuccin_mocha.theme \
    -o "$HOME/.config/btop/themes/catppuccin_mocha.theme" 2>/dev/null || true
fi

# 8. Activar los hooks versionados del repo (pre-commit con el harness)
if [ "$DRY_RUN" = true ]; then
  echo "  [DRY-RUN] git config core.hooksPath scripts/hooks"
else
  git -C "$DOTFILES_DIR" config core.hooksPath scripts/hooks 2>/dev/null || true
fi

# 9. Compilar herdr-ctl
if [ "$DRY_RUN" = true ]; then
  echo "  [DRY-RUN] Validando compilación de herdr-ctl (go vet + build dry-run)..."
  (
    cd "$DOTFILES_DIR/tools/herdr-ctl"
    go vet ./...
    # Sin `go test`: los tests de herdr-ctl los corre scripts/harness-quick.sh. Mantenerlos aquí acoplaba un test de Go
    # en rojo (fase roja de TDD) con el dry-run y con los checks de test-zshenv que lo ejecutan.
    go build -o /dev/null .
  )
  echo "  ✓ herdr-ctl compila sin advertencias."
else
  echo "==> Compilando herdr-ctl..."
  (
    cd "$DOTFILES_DIR/tools/herdr-ctl"
    go build -ldflags="-s -w" -o "$HOME/.local/bin/herdr-ctl"
  )
fi

fi

echo "============================================================"
if [ "$LINKS_ONLY" = true ]; then
  echo "✓ --links-only: directorios y enlaces listos bajo $HOME."
elif [ "$DRY_RUN" = true ]; then
  echo "✓ [DRY-RUN] Prueba de humo de install.sh superada!"
  echo "  Todas las dependencias, rutas y compilaciones son válidas."
else
  echo "✓ Instalación completada."
  echo "Para recargar tu shell: exec zsh"
fi
echo "============================================================"
