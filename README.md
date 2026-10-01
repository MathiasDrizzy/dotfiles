# Dotfiles macOS — setup de terminal

Configuración de terminal para macOS (Apple Silicon): **Ghostty + herdr + zsh + Catppuccin Mocha**, con las TUIs del día a día. Está pensada para reinstalarla entera tras formatear.

## Estructura

```
dotfiles/
├── mac/
│   ├── install.sh              # instalación idempotente (--dry-run, --links-only)
│   ├── zshrc / zshenv          # shell interactivo y PATH global
│   ├── config/                 # ghostty, herdr, yazi, micro, starship, termscp, lazygit, lazydocker, btop, bat
│   ├── scripts/                # check-links.sh, herdr-reload.sh, terminal-popup.sh
│   └── tools/herdr-ctl/        # herramienta en Go: cheatsheet, adapt, bus de agentes, keys-check
└── scripts/
    ├── harness-quick.sh        # harness rápido (lo corre el pre-commit)
    ├── harness-behavior.py     # harness de comportamiento sobre un herdr aislado
    └── hooks/                  # pre-commit y post-commit versionados (core.hooksPath)
```

## Instalación en un Mac nuevo

```bash
git clone https://github.com/MathiasDrizzy/dotfiles.git ~/dotfiles
cd ~/dotfiles/mac
./install.sh            # instala paquetes, enlaza configs, compila herdr-ctl y activa los hooks
exec zsh
```

* `./install.sh --dry-run`: simula todo y no modifica nada.
* `./install.sh --links-only`: solo crea directorios y enlaces simbólicos bajo `$HOME`; no instala paquetes, no descarga temas y no compila. Sirve para probar en un HOME temporal: `HOME=$(mktemp -d) ./install.sh --links-only`.
* `mac/scripts/check-links.sh` verifica que `~/.config/...` apunte al repo (`--fix` repara con copia de seguridad).

## Atajos de herdr (`prefix = ctrl+b`)

La lista completa y vigente está en el cheatsheet: **`ctrl+b → h`**. Se genera al abrirlo desde `herdr --default-config` más `mac/config/herdr/config.toml`, así que no puede listar atajos que no existen. Cerrar con `q` o `Esc`; `/` filtra.

Lo que añade este repo sobre los defaults de herdr:

| Atajo | Qué hace |
|---|---|
| `ctrl+b → ← ↑ ↓ →` | Mover el foco entre cuadros (reemplaza a `h j k l`) |
| `ctrl+b → Shift+← ↑ ↓ →` | Intercambiar el cuadro con su vecino |
| `ctrl+b → h` | Cheatsheet |
| `ctrl+b → t` | Terminal popup (scratchpad); se cierra con `Esc` (prompt vacío), `Ctrl+Q`, `Ctrl+D` o `exit` |
| `ctrl+b → m` | Ajusta el ancho del sidebar a la pantalla (`herdr-ctl adapt`) |
| `ctrl+b → f` / `Shift+F` | Sidebar explorer / quick open |
| `ctrl+b → Shift+C` | Mover el cuadro a una pestaña nueva |
| `ctrl+b → < / >` | Reordenar pestañas |
| `ctrl+b → Shift+R` / `Shift+Q` | Refrescar cuotas de agentes / sus ajustes (reemplaza a `reload_config`; recarga el config con `herdr server reload-config`) |

`herdr-ctl keys-check` compara cada atajo del repo con los defaults de herdr y avisa de colisiones.

## herdr-ctl (Go, `mac/tools/herdr-ctl`)

```bash
herdr-ctl adapt [laptop|external]   # ancho del sidebar: 24 cols (Mac) / 22 cols (monitor ultra-ancho)
herdr-ctl cheatsheet                # el popup de ctrl+b → h
herdr-ctl keys-check                # colisiones de atajos contra los defaults de herdr
herdr-ctl move-tab new              # mover el cuadro actual a una pestaña nueva
herdr-ctl status                    # paneles de herdr por el socket
```

### Bus de agentes por el socket de herdr

Canal con el agente de reserva `agy` (y cualquier otro agente en un cuadro de herdr):

```bash
swarm | agents          # estado del enjambre
aprompt <agente> <msg>  # enviar un prompt a otro agente   (herdr-ctl prompt)
aread <agente>          # leer su salida                   (herdr-ctl read)
afocus <agente>         # saltar a su cuadro               (herdr-ctl focus)
```

## Aliases (en `mac/zshrc`)

`lg` lazygit · `ld` lazydocker · `sftp` termscp · `hosts` sshs · `y` yazi (deja la shell en la carpeta donde sales) · `sb`, `sb-ext`, `sb-lap`, `sb-auto` sidebar · `agy` Antigravity CLI (agente de reserva) · `claude` Claude Code · `brewup`, `brewout` Homebrew.

## Desarrollo y harness

```bash
git config core.hooksPath scripts/hooks   # lo hace install.sh
scripts/harness-quick.sh                  # rápido: sin datos de red local, sintaxis, go vet/test, keys-check
python3 scripts/harness-behavior.py -v    # abre un herdr aislado y prueba los atajos de verdad
```

* El **pre-commit** corre el harness rápido y, si el commit toca herdr, scripts o `zshrc`, también el de comportamiento.
* El **harness de comportamiento** usa un HOME temporal y una sesión propia (no toca tu herdr): comprueba que `prefix+h` abre el cheatsheet y `q`/`Esc` lo cierran, que el popup de terminal cierra con `Esc`, que `prefix+m` cambia el ancho del sidebar, que las flechas mueven el foco, que `Shift+flechas` intercambian cuadros y que `prefix+Shift+R` ejecuta el comando del repo.
* El repo es **público**: nada de IPs de la red local, hostnames, contraseñas ni tokens (lo vigila el harness).
