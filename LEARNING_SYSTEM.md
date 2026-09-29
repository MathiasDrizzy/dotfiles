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

---

## 2. Protocolo de Extensión de Regresión
Cada vez que el usuario reporte que "algo dejó de funcionar después de modificar otra cosa":
1. **Identificar la aserción que faltaba:** ¿Fue un error de TOML, un conflicto de teclas, una ruta rota o un fallo de compilación?
2. **Agregar la prueba a `harness/validate_configs.py`:** Escribir una función `test_<nuevo_aspecto>()`.
3. **Validar que el test falle antes del arreglo y pase después del arreglo (TDD).**
4. **Registrar el aprendizaje en este documento.**
