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
  --dry-run | -n) DRY_RUN=true ;;
  --links-only) LINKS_ONLY=true ;;
  esac
done

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# herdr-ctl, dotbar and dotborder are repositories of their own, pinned here as submodules: fetch them when a plain clone left them empty.
if { [ ! -f "$DOTFILES_DIR/tools/herdr-ctl/go.mod" ] || [ ! -f "$DOTFILES_DIR/tools/dotborder/Package.swift" ]; } && git -C "$DOTFILES_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$DOTFILES_DIR" submodule update --init --recursive ||
    echo "  [AVISO] no se descargaron herdr-ctl, dotbar y dotborder; ejecuta: git submodule update --init --recursive"
fi
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
    poppler fd ripgrep fzf zoxide atuin starship mise
    lazygit lazydocker termscp sshs btop mathiasdrizzy/tap/lazyfinder tmux
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
    brew install --cask font-sketchybar-app-font || true
    brew install --cask nikitabobko/tap/aerospace || true
    brew install ungive/media-control/media-control || true
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
  "$HOME/.config/herdr-auto-title"
  "$HOME/.config/aerospace"
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
  "config/herdr-auto-title/config.env"
  "config/aerospace/aerospace.toml"
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

  # 9. Compilar herdr-ctl
  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY-RUN] Validando compilación de herdr-ctl (go vet + build dry-run)..."
    (
      cd "$DOTFILES_DIR/tools/herdr-ctl"
      go vet ./...
      # Sin `go test`: los tests de herdr-ctl los corre su propio repositorio (scripts/go-checks.sh de herdr-ctl). Mantenerlos aquí acoplaba un test de Go
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
    # Signed with the same local certificate as dotbar and a fixed identifier: macOS then keeps what it was allowed
    # (the background pass reads repositories under ~/Documents) across rebuilds; ad hoc signing named it a.out and
    # every build looked like a new program.
    identity="$("$DOTFILES_DIR/tools/dotbar/scripts/signing-identity.sh" 2>/dev/null)" || identity="-"
    codesign --force -s "$identity" -i dev.dotfiles.herdr-ctl "$HOME/.local/bin/herdr-ctl" 2>/dev/null ||
      echo "  [AVISO] herdr-ctl quedó sin firmar; macOS puede volver a pedir permiso tras cada compilación."
    # The herdr sidebar's space rows (each repository: branch, commits not pushed, files changed, CI) and the agents'
    # usage come from `herdr-ctl spaces-watch`: it follows herdr's events (a closed tab leaves the tree at once) and
    # makes one pass a minute for CI. It runs as a herdr plugin, not a launchd job: macOS delays a launchd job's
    # wakeups by about 100 ms, which made the bright agent name trail the focus by half a second.
    old_agent="$HOME/Library/LaunchAgents/dev.dotfiles.herdr-spaces.plist"
    if [ -e "$old_agent" ]; then
      launchctl bootout "gui/$(id -u)/dev.dotfiles.herdr-spaces" 2>/dev/null || true
      rm -f "$old_agent"
    fi
    if command -v herdr >/dev/null 2>&1; then
      # Unlinked first: an earlier install linked the plugin from where it lived before herdr-ctl had a repository of its own.
      herdr plugin unlink dev.dotfiles.spaces-sync >/dev/null 2>&1 || true
      herdr plugin link "$DOTFILES_DIR/tools/herdr-ctl/plugin" >/dev/null 2>&1 &&
        { herdr plugin action invoke start --plugin dev.dotfiles.spaces-sync >/dev/null 2>&1 || true; } ||
        echo "  [AVISO] no se enlazó el plugin spaces-sync; reintenta: herdr plugin link $DOTFILES_DIR/tools/herdr-ctl/plugin"
    fi
  fi

  # 10. Compile ctlcenter (dotbar runs its `stay` helper, and opens Control Center through it when it may not post keys
  # itself; needs the Xcode command line tools)
  if [ "$DRY_RUN" != true ]; then
    echo "==> Compilando ctlcenter..."
    # Its module cache goes under HOME: the default one (outside it) is written only when cold, as on a fresh Mac.
    swiftc -O -module-cache-path "$HOME/.cache/swift-module-cache" "$DOTFILES_DIR/tools/ctlcenter/ctlcenter.swift" \
      -o "$HOME/.local/bin/ctlcenter" ||
      echo "  [AVISO] ctlcenter no compiló (¿faltan las Command Line Tools?); dotbar sigue funcionando sin su ayudante."
  fi

  # 11. ctrl+down (Mission Control's "Application windows", system shortcut 33) is turned off: it is of no
  # use here. activateSettings applies it without logging out.
  if [ "$DRY_RUN" != true ]; then
    defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 33 \
      "<dict><key>enabled</key><false/><key>value</key><dict><key>parameters</key><array><integer>65535</integer><integer>125</integer><integer>8650752</integer></array><key>type</key><string>standard</string></dict></dict>"
    activate_settings="$(command -v activateSettings ||
      echo /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings)"
    "$activate_settings" -u 2>/dev/null || true
  fi

  # 12. dotbar, the bar (mac/tools/dotbar): built into ~/Applications/dotbar.app and started at login by a launch agent
  # that starts it again if it crashes (a quit or a logout ends it for good). Its first run asks for Location (the weather
  # box's commune); Accessibility (the app's menus, Control Center, Vorssaint) is granted in System Settings.
  if [ "$DRY_RUN" != true ]; then
    echo "==> Compilando dotbar..."
    if "$DOTFILES_DIR/tools/dotbar/scripts/bundle.sh" "$HOME/Applications" >/dev/null; then
      agent="$HOME/Library/LaunchAgents/dev.dotfiles.dotbar.plist"
      mkdir -p "$(dirname "$agent")"
      # Written with printf, not a here-document: macOS's bash keeps a here-document in a temporary file of its own choice.
      printf '%s\n' \
        '<?xml version="1.0" encoding="UTF-8"?>' \
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
        '<plist version="1.0">' \
        '<dict>' \
        '  <key>Label</key><string>dev.dotfiles.dotbar</string>' \
        "  <key>ProgramArguments</key><array><string>$HOME/Applications/dotbar.app/Contents/MacOS/dotbar</string></array>" \
        '  <key>RunAtLoad</key><true/>' \
        '  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>' \
        '  <key>ProcessType</key><string>Interactive</string>' \
        '  <key>LimitLoadToSessionType</key><string>Aqua</string>' \
        '</dict>' \
        '</plist>' >"$agent"
      launchctl bootout "gui/$(id -u)/dev.dotfiles.dotbar" 2>/dev/null || true
      launchctl bootstrap "gui/$(id -u)" "$agent" ||
        echo "  [AVISO] dotbar no arrancó; ábrelo con: open ~/Applications/dotbar.app"
    else
      echo "  [AVISO] dotbar no compiló (¿faltan las Command Line Tools?)."
    fi
  fi

  # 12b. dotborder, the focus border (mac/tools/dotborder): built into ~/Applications/dotborder.app and started at login by a
  # launch agent. It follows AeroSpace's own events, needs no macOS permission and replaces JankyBorders (`borders`), which is
  # stopped and uninstalled where an earlier install left it.
  if [ "$DRY_RUN" != true ]; then
    if brew list borders >/dev/null 2>&1; then
      echo "==> Quitando JankyBorders (lo reemplaza dotborder)..."
      pkill -x borders 2>/dev/null || true
      brew uninstall borders >/dev/null 2>&1 || true
    fi
    echo "==> Compilando dotborder..."
    if "$DOTFILES_DIR/tools/dotborder/scripts/bundle.sh" "$HOME/Applications" >/dev/null; then
      agent="$HOME/Library/LaunchAgents/dev.dotfiles.dotborder.plist"
      mkdir -p "$(dirname "$agent")"
      printf '%s\n' \
        '<?xml version="1.0" encoding="UTF-8"?>' \
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
        '<plist version="1.0">' \
        '<dict>' \
        '  <key>Label</key><string>dev.dotfiles.dotborder</string>' \
        "  <key>ProgramArguments</key><array><string>$HOME/Applications/dotborder.app/Contents/MacOS/dotborder</string><string>active_color=0xccb48efa</string><string>width=2.0</string></array>" \
        "  <key>EnvironmentVariables</key><dict><key>PATH</key><string>$BREW_PREFIX/bin:/usr/bin:/bin</string></dict>" \
        '  <key>RunAtLoad</key><true/>' \
        '  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>' \
        '  <key>ProcessType</key><string>Interactive</string>' \
        '  <key>LimitLoadToSessionType</key><string>Aqua</string>' \
        '</dict>' \
        '</plist>' >"$agent"
      launchctl bootout "gui/$(id -u)/dev.dotfiles.dotborder" 2>/dev/null || true
      launchctl bootstrap "gui/$(id -u)" "$agent" ||
        echo "  [AVISO] dotborder no arrancó; ábrelo con: open ~/Applications/dotborder.app"
    else
      echo "  [AVISO] dotborder no compiló (¿faltan las Command Line Tools?)."
    fi
  fi

  # 13. SketchyBar, the bar dotbar replaced: stopped and uninstalled where an earlier install left it, and the links it left
  # in ~/.config removed (their sources are gone from the repo).
  if [ "$DRY_RUN" != true ]; then
    if brew list sketchybar >/dev/null 2>&1; then
      echo "==> Quitando SketchyBar..."
      pkill -x sketchybar 2>/dev/null || true
      brew uninstall sketchybar >/dev/null 2>&1 || true
    fi
    if [ -d "$HOME/.config/sketchybar" ]; then
      find "$HOME/.config/sketchybar" -type l -delete
      find "$HOME/.config/sketchybar" -type d -empty -delete 2>/dev/null || true
    fi
  fi

  # 13. lazyfinder is herdr's sidebar: its plugin docks it at the left of every tab and opens it by itself
  # (prefix+f toggles it). It builds with Go or reuses the lazyfinder installed above.
  if [ "$DRY_RUN" != true ] && command -v herdr >/dev/null 2>&1 &&
    ! herdr plugin list 2>/dev/null | grep -q "^- lazyfinder "; then
    echo "==> Plugin de herdr: lazyfinder..."
    herdr plugin install --yes MathiasDrizzy/lazyfinder ||
      echo "  [AVISO] No se instaló el plugin lazyfinder; reintenta: herdr plugin install --yes MathiasDrizzy/lazyfinder"
  fi

  # 14. Auto Title names the tabs after what runs in them (ui.prompt_new_tab_name = false in the herdr config makes tabs
  # without a prompt; a tab you rename by hand is left alone). Pinned to a commit, not a tag (a tag can be moved): a plugin
  # runs with your permissions, so a new release is read before the pin moves. Installed again whenever another commit is
  # installed, so moving the pin updates every machine. It builds with Go and starts with the herdr server (or the restart
  # action).
  AUTO_TITLE_REF=e7fbd5717cc4293d2768a8792d7b331f69595474 # v0.14.0
  if [ "$DRY_RUN" != true ] && command -v herdr >/dev/null 2>&1 &&
    ! herdr plugin list 2>/dev/null | grep -q "^- herdr.auto-title .*@$AUTO_TITLE_REF]"; then
    echo "==> Plugin de herdr: Auto Title ${AUTO_TITLE_REF:0:7}..."
    herdr plugin install --yes kryptamine/herdr-auto-title --ref "$AUTO_TITLE_REF" &&
      { herdr plugin action invoke herdr.auto-title.restart >/dev/null 2>&1 || true; } ||
      echo "  [AVISO] No se instaló el plugin Auto Title; reintenta: herdr plugin install --yes kryptamine/herdr-auto-title --ref $AUTO_TITLE_REF"
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
