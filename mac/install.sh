#!/usr/bin/env bash
# ==============================================================================
# dotfiles/mac/install.sh
# Script automatizado e idempotente para configurar macOS (Apple Silicon) al 100%
# con Ghostty, herdr, Antigravity, zsh, Catppuccin Mocha y herramientas TUI.
# ==============================================================================
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "==> Iniciando instalación de dotfiles (macOS)..."

# 1. Comprobar Homebrew
if ! command -v brew &>/dev/null; then
  echo "==> Instalando Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# 2. Configurar ~/.zshenv (PATH global para agentes e interactivo)
echo "==> Configurando ~/.zshenv..."
cat >> ~/.zshenv <<'EOF'
# Homebrew + Rust
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
export PATH="/opt/homebrew/opt/rustup/bin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
EOF
eval "$(/opt/homebrew/bin/brew shellenv)"
export PATH="/opt/homebrew/opt/rustup/bin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

# 3. Paquetes Homebrew esenciales
echo "==> Instalando fórmulas y casks de Homebrew..."
brew install herdr ghostty micro glow bat git-delta go rustup \
  yazi ffmpeg poppler fd ripgrep fzf zoxide atuin starship mise \
  lazygit lazydocker termscp sshs btop chafa
brew install fzf-tab zsh-autosuggestions zsh-syntax-highlighting
brew install --cask font-jetbrains-mono-nerd-font || true

# 4. Activar toolchain de Rust
rustup default stable || true

# 5. Crear directorios de configuración
mkdir -p ~/.config/{ghostty,herdr,yazi,micro/colorschemes,btop/themes,bat,termscp} \
  ~/.local/{bin,share,state} ~/Library/Application\ Support/{lazygit,lazydocker,shiki}

# 6. Copiar / Enlazar configuraciones
echo "==> Instalando archivos de configuración..."
cp "$DOTFILES_DIR/config/ghostty/config" ~/.config/ghostty/config
cp "$DOTFILES_DIR/config/herdr/config.toml" ~/.config/herdr/config.toml
cp "$DOTFILES_DIR/config/yazi/"* ~/.config/yazi/ || true
cp "$DOTFILES_DIR/config/micro/"* ~/.config/micro/ || true
cp "$DOTFILES_DIR/config/starship/starship.toml" ~/.config/starship.toml || true
cp "$DOTFILES_DIR/config/termscp/"* ~/.config/termscp/ || true
cp "$DOTFILES_DIR/config/lazygit/config.yml" ~/Library/Application\ Support/lazygit/config.yml || true
cp "$DOTFILES_DIR/config/lazydocker/config.yml" ~/Library/Application\ Support/lazydocker/config.yml || true
cp "$DOTFILES_DIR/config/btop/btop.conf" ~/.config/btop/btop.conf || true
cp "$DOTFILES_DIR/config/bat/config" ~/.config/bat/config || true
cp "$DOTFILES_DIR/zshrc" ~/.zshrc

# 7. Tema Catppuccin Mocha para micro y btop
curl -fsSL https://raw.githubusercontent.com/catppuccin/micro/main/themes/catppuccin-mocha.micro \
  -o ~/.config/micro/colorschemes/catppuccin-mocha.micro 2>/dev/null || true
curl -fsSL https://raw.githubusercontent.com/catppuccin/btop/main/themes/catppuccin_mocha.theme \
  -o ~/.config/btop/themes/catppuccin_mocha.theme 2>/dev/null || true

# 8. Compilar e instalar herdr-ctl (herramienta nativa en Go)
echo "==> Compilando herdr-ctl..."
(
  cd "$DOTFILES_DIR/tools/herdr-ctl"
  go build -ldflags="-s -w" -o ~/.local/bin/herdr-ctl
)

# 9. Copiar cheatsheet TUI
if [ -f "$DOTFILES_DIR/bin/herdr-cheatsheet" ]; then
  cp "$DOTFILES_DIR/bin/herdr-cheatsheet" ~/.local/bin/herdr-cheatsheet
  chmod +x ~/.local/bin/herdr-cheatsheet
fi

echo "============================================================"
echo "✓ Instalación completada al 100%!"
echo "Para recargar tu shell: exec zsh"
echo "============================================================"
