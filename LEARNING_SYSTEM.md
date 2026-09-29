# 🧠 LEARNING_SYSTEM.md — Memoria de Errores y Auto-Aprendizaje (Dotfiles)

> **Ubicación:** `/Users/drizzy/Documents/proyectos/dotfiles/LEARNING_SYSTEM.md`  
> **Objetivo:** Registro de fallos previos, causa raíz y mecanismos preventivos implementados en el harness.  

---

## 1. Registro de Incidentes Previos y Causa Raíz

### Incidente 01: El bug de "Rename" involuntario en `shiki`
* **Síntoma:** Al abrir `shiki` dentro de un panel de herdr, el título del panel se reescribía automáticamente o entraba en bucle de renombrado.
* **Causa Raíz:** `shiki` emitía códigos de escape ANSI/OSC (OSC 10/11) para consultar los colores de fondo de la terminal. Al no recibir respuesta inmediata del multiplexer herdr, interpretaba la respuesta de la terminal como texto entrante.
* **Solución Implementada:** Se creó un script wrapper con la variable `SHIKI_NO_TERM_QUERY=1`.
* **Lección Permanente:** Cualquier TUI que se integre debe probarse dentro de herdr verificando que no emita consultas OSC no soportadas.

### Incidente 02: Conflictos entre atajos Vim y atajos Nativos de herdr
* **Síntoma:** Intentos de configurar `ctrl+b h/j/k/l` para mover paneles colisionaban con `ctrl+b h` (cheatsheet) y rompían la ergonomía de navegación.
* **Causa Raíz:** Falta de un validador que detectara colisiones de atajos a nivel de parseo de TOML.
* **Solución Implementada:** Se unificó la navegación en flechas nativas (`focus_pane_*` en Rust) y se construyó el validador en `harness/validate_configs.py` que detecta colisiones de teclas antes del commit.
* **Lección Permanente:** Nunca introducir teclas vim a ciegas en `keys.command`.

### Incidente 03: Desajuste de columnas de sidebar en monitores ultra-wide
* **Síntoma:** El sidebar de `yazi` o el explorer quedaba demasiado estrecho o demasiado ancho al cambiar de pantalla integrada a monitor 21:9.
* **Causa Raíz:** herdr no soportaba porcentaje dinámico por monitor en la versión instalada.
* **Solución Implementada:** Creación de `herdr-ctl adapt` en Go que ajusta las columnas de forma inteligente según la resolución detectada.

### Incidente 04: Fragilidad de binarios parcheados (Retiro definitivo de `shiki`)
* **Síntoma:** `shiki` requería un binario parcheado a mano (`shiki-patched`), hacks de entorno (`SHIKI_NO_TERM_QUERY=1`) y se rompía con cualquier `brew upgrade`, arriesgando bucles de escape ANSI en paneles de herdr.
* **Causa Raíz:** Dependencia de un software de terceros con sondeos de terminal que no respetaba el entorno multiplexado.
* **Solución Implementada:** Sustitución completa de `shiki` por `notes-manager` (`mac/scripts/notes-manager.sh`), un gestor TUI nativo que combina `fzf` (interactivo Catppuccin Mocha), `glow` (previsualización Markdown en vivo) y `micro` (edición directa) en un popup herdr (`prefix + o`). Cero secuencias OSC, cero binarios parcheados y almacenamiento 100% plano en `~/Documents/notes`.
* **Lección Permanente:** Privilegiar herramientas desacopladas en Markdown plano y componibles con el stack estándar (`fzf`, `micro`, `glow`) antes que binarios monolíticos opacos.

### Incidente 05: Drift de configuraciones locales editadas fuera de Git
* **Síntoma:** Modificaciones hechas en `~/.config/...` se perdían o no se reflejaban en el repositorio git, o generaban discrepancias silenciosas (ej: variables de audio o colores).
* **Causa Raíz:** Falta de auditoría bidireccional entre `~/.config/...` y `~/dotfiles/mac/config/...`.
* **Solución Implementada:** Creación de `mac/scripts/check-links.sh` que audita automáticamente cada archivo, detecta drifts con `diff -u` y permite sincronizar con `--fix` mediante enlaces simbólicos y backups automáticos `.bak`.
* **Lección Permanente:** Todos los dotfiles deben estar enlazados simbólicamente o auditados por el harness antes de cada commit.

### Incidente 06: Fricción en recarga de configuraciones de herdr
* **Síntoma:** Tras editar `config.toml`, era necesario reiniciar Ghostty o matar el servidor herdr interrumpiendo procesos en ejecución.
* **Causa Raíz:** Desconocimiento del socket Unix de herdr (`~/.config/herdr/herdr.sock`) y del comando `herdr server reload-config`.
* **Solución Implementada:** Implementación de `mac/scripts/herdr-reload.sh`, hook git `post-commit` y comando nativo `herdr-ctl reload` en Go, permitiendo recarga en caliente instantánea sin interrumpir agentes ni pestañas.

### Incidente 07: Ausencia de pruebas de humo para `install.sh`
* **Síntoma:** El instalador podía romperse por rutas faltantes o sintaxis en shell sin que el harness lo advirtiera.
* **Causa Raíz:** `install.sh` carecía de un modo seguro no destructivo (`--dry-run`) para ser ejecutado en CI/harness.
* **Solución Implementada:** Añadido soporte de `--dry-run` a `mac/install.sh` y prueba de humo `test_install_script_dry_run()` en `harness/validate_configs.py`.

---

## 2. Protocolo de Extensión de Regresión
Cada vez que el usuario reporte que "algo dejó de funcionar después de modificar otra cosa":
1. **Identificar la aserción que faltaba:** ¿Fue un error de TOML, un conflicto de teclas, una ruta rota o un fallo de compilación?
2. **Agregar la prueba a `harness/validate_configs.py`:** Escribir una función `test_<nuevo_aspecto>()`.
3. **Validar que el test falle antes del arreglo y pase después del arreglo (TDD).**
4. **Registrar el aprendizaje en este documento.**
