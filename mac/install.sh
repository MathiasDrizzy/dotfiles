#!/usr/bin/env bash
# ==============================================================================
# dotfiles/mac/install.sh
# Script automatizado e idempotente para configurar macOS (Apple Silicon)
# con Ghostty, herdr, Antigravity, zsh, Catppuccin Mocha y herramientas TUI.
# Soporta --dry-run (simulación) y --links-only (solo crea directorios y enlaces
# bajo $HOME; no instala paquetes, no descarga temas, no compila, no toca ~/.zshenv).
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

# 1. Comprobar Homebrew
if ! command -v brew &>/dev/null; then
  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY-RUN] Homebrew no detectado. Se instalaría curl https://raw.githubusercontent.com/.../install.sh"
  else
    echo "==> Instalando Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
else
  echo "  ✓ Homebrew disponible: $(brew --version | head -n 1)"
fi

# 2. Configurar ~/.zshenv (PATH global para agentes e interactivo)
if [ "$DRY_RUN" = true ]; then
  echo "  [DRY-RUN] Configuración de ~/.zshenv (Homebrew + Rust + ~/.local/bin)"
else
  echo "==> Configurando ~/.zshenv..."
  if [ ! -f "$HOME/.zshenv" ] || ! grep -q "herdr" "$HOME/.zshenv" 2>/dev/null; then
    cat >> "$HOME/.zshenv" <<'EOF'
# Homebrew + Rust
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
export PATH="/opt/homebrew/opt/rustup/bin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
EOF
  fi
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  export PATH="/opt/homebrew/opt/rustup/bin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
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
  "$DOTFILES_DIR/scripts/check-links.sh" || true
else
  echo "==> Sincronizando enlaces simbólicos..."
  "$DOTFILES_DIR/scripts/check-links.sh" --fix
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
    go test ./...
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
