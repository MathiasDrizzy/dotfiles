# 🚀 Dotfiles macOS — Terminal Powerhouse

Configuración ultra-optimizada para macOS (Apple Silicon) con **Ghostty + herdr + Antigravity + zsh + Catppuccin Mocha**.

---

## 📁 Estructura

```
dotfiles/
└── mac/
    ├── install.sh              # Script maestro de instalación idempotente
    ├── zshrc                   # Configuración interactiva zsh
    ├── zshenv                  # PATH global para subprocesos y agentes
    ├── config/                 # Configuraciones Catppuccin Mocha
    │   ├── ghostty/            # Terminal Ghostty (opacidad 0.85, blur 40, Catppuccin)
    │   ├── herdr/              # Terminal multiplexer para agentes de IA
    │   ├── yazi/               # Explorador de archivos TUI
    │   ├── micro/              # Editor de texto terminal
    │   ├── starship/           # Prompt Starship minimalista
    │   ├── termscp/            # Cliente SFTP/FTP gráfico
    │   ├── lazygit/            # TUI Git
    │   ├── lazydocker/         # TUI Docker
    │   ├── btop/               # Monitor del sistema
    │   └── bat/                # Pager con resaltado de sintaxis
    └── tools/
        └── herdr-ctl/          # Herramienta nativa en Go (adaptador de sidebar + cheatsheet TUI)
```

---

## 🛠 Instalación en un Mac nuevo

```bash
git clone https://github.com/MathiasDrizzy/dotfiles.git ~/dotfiles
cd ~/dotfiles/mac
./install.sh
exec zsh
```

---

## ⚡ Herramienta Nativa: `herdr-ctl` (Go)

Ubicada en `mac/tools/herdr-ctl/`:
* Conexión por socket Unix nativo (`~/.config/herdr/herdr.sock`).
* Detección dinámica de resolución y ancho de terminal.
* Auto-ajuste de proporciones del sidebar sin reiniciar paneles:
  * **Pantalla integrada de Mac:** 24 columnas.
  * **Monitor Ultra-Wide (2560x1080):** 22 columnas.

```bash
herdr-ctl adapt           # Auto-detecta la pantalla actual y ajusta
herdr-ctl adapt laptop    # Fuerza modo laptop (24 cols)
herdr-ctl adapt external  # Fuerza modo monitor ultra-ancho (22 cols)
herdr-ctl status          # Consulta estado y paneles de herdr
```

---

## 🎹 Atajos Principales de `herdr` (`prefix = ctrl+b`)

### 🪟 Gestión de Paneles y Pestañas (Non-Vim, nativo con Flechas)
* `ctrl+b → ↑ ↓ ← →` : Moverse entre cuadros de trabajo.
* `ctrl+b → Shift+↑/↓/←/→` : Intercambiar posición de cuadros (swap).
* `ctrl+b → Shift+C` : Mover el cuadro actual a una **NUEVA** pestaña.
* `ctrl+b → > / <` : Reordenar pestañas a la derecha o izquierda.
* `ctrl+b → z` : Zoom / pantalla completa del cuadro enfocado.
* `ctrl+b → % / "` : Split vertical / horizontal.
* `ctrl+b → x` : Cerrar cuadro actual.

### ⚡ Popups y Herramientas Flotantes
* `ctrl+b → h` : **Cheatsheet interactivo** (popup con búsqueda `/` y todos los comandos).
* `ctrl+b → t` : **Terminal popup (Scratchpad)** (terminal flotante para `sftp`, `hosts`, etc., cerrar con `Esc`, `Ctrl+D` o `exit`).
* `ctrl+b → m` : **Auto-adaptar sidebar** según el monitor actual con `herdr-ctl`.
* `ctrl+b → f` : Abrir / enfocar / alternar sidebar explorer.
* `ctrl+b → Shift+F` : Búsqueda rápida de archivos (Quick Open tipo Ctrl+P).
* `ctrl+b → Shift+Q` : Configuración de cuotas de modelos (agent-usage).
* `ctrl+b → Shift+R` : Refrescar cuotas de agentes.

### 🐚 Aliases Útiles en Terminal
* `sftp` : Lanza `termscp` (explorador SFTP/FTP/S3).
* `hosts` : Lanza `sshs` (selector visual de servidores SSH).
* `notes` : Gestor de notas interactivo (`notes-manager`).
* `lg` : `lazygit`.
* `ld` : `lazydocker`.
* `y` : `yazi` (al salir te deja en el directorio navegado).
