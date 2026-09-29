# 🔬 TUI Notes Research: Alternativas Superiores a Shiki para macOS + herdr

> **Investigador:** Cerebro Maestro & Agente Dotfiles  
> **Fecha:** 2026-09-29  
> **Stack Actual:** macOS (Apple Silicon), Ghostty, herdr, Catppuccin Mocha, micro, yazi.  

---

## 1. Diagnóstico de Shiki: ¿Por qué resulta insatisfactorio?

1. **Inestabilidad con Multiplexers:** Shiki requiere hacks de entorno (`SHIKI_NO_TERM_QUERY=1`) y un binario parcheado a mano (`shiki-patched`) porque emite secuencias OSC ANSI de sondeo de color que confunden a herdr provocando intentos involuntarios de renombrar paneles.
2. **UX Rígida / No Convencional:** Su navegación modal híbrida y la gestión de notebooks en SQLite/Git interno genera fricción al querer buscar rápido o editar una nota con un editor externo familiar (`micro`).
3. **Mantenibilidad:** Actualizar Shiki (`brew upgrade`) rompe el binario parcheado obligando a recompilar desde código fuente cada vez.

---

## 2. Comparativa Técnica de las Mejores Alternativas

| Herramienta | Lenguaje / Stack | Tipo de Interfaz | Almacenamiento | Integración Editor | Veredicto |
|---|---|---|---|---|---|
| **`nb`** | Shell / CLI / TUI | TUI interactiva + CLI veloz | Archivos `.md` planos + Git automático | Nativo (`micro`, `nvim`, nano) | 🏆 **Máxima madurez y versatilidad** |
| **`zk`** | Go / Rust | FZF TUI + CLI + LSP | Markdown plano + Zettelkasten | Nativo (`micro` / `nvim`) | ⚡ **Ultra-rápido para notas interconectadas** |
| **`toney` / `note`** | Go (Bubbletea) | TUI moderna de 2 paneles | Markdown local en `~/.note` | `nvim` / `micro` | ✨ **Estética visual limpia y moderna** |
| **`clin-rs`** | Rust | TUI estilo Obsidian (3 paneles) | Markdown + canvas | Editor interno + visualizador | 🧠 **Ideal si buscas un Obsidian en terminal** |
| **`fzf + micro + glow`** | Scripts nativos | Popup TUI nativo en herdr | Carpeta `~/Notes` | 100% integrado a tu stack actual | 🎯 **Cero dependencias nuevas, 100% bajo control** |

---

## 3. Las Dos Mejores Recomendaciones para Mathias

### Opción A (Recomendada): `nb` (The Terminal Notebook)
* **¿Por qué es superior?** 
  - Instalable vía Homebrew con un solo comando: `brew install nb`.
  - Guarda tus notas como archivos Markdown 100% normales en `~/.nb`.
  - Control de versiones con Git transparente (hace commits automáticos).
  - Búsqueda全文 ultra veloz con `ripgrep` o `grep`.
  - Modo interactivo tipo TUI (`nb browse` o `nb gui`) y modo CLI para capturar ideas al vuelo (`nb add "recordar actualizar terraform"`).
  - Al presionar enter, abre tu editor preferido (`micro`) configurado en tus dotfiles.

### Opción B: Script Nativo de Popup (`fzf` + `glow` + `micro`)
* Si no quieres depender de herramientas externas complejas:
  - Crear un script ligero en `mac/scripts/notes-manager.sh` que abre un popup en herdr (`ctrl+b o`).
  - Lado izquierdo: lista de notas con búsqueda instantánea en `fzf`.
  - Lado derecho: vista previa formateada en Catppuccin con `glow`.
  - Al pulsar Enter: abre la nota en `micro` para editar.
  - Al guardar: commitea y sincroniza automáticamente.

---

## 4. Decisión Final e Implementación (2026-09-29)

* **Elección:** **Opción B (`mac/scripts/notes-manager.sh`)**
* **Atajo herdr:** `prefix + o` (`type = "popup"`, dimensiones `85% x 85%`)
* **Ubicación de notas:** `$HOME/Documents/notes`
* **Justificación técnica:**
  1. **Cero dependencias pesadas:** Evita la instalación de `nb` que arrastra dependencias de gran tamaño (`pandoc`, `tig`, `w3m`, `nmap`). Las herramientas `fzf`, `glow` y `micro` ya forman parte del núcleo de los dotfiles.
  2. **Inmunidad a problemas OSC/ANSI:** No realiza sondeos de color de terminal a bajo nivel, eliminando al 100% el bug de renombrado involuntario que provocaba `shiki`.
  3. **Ergonomía superior en herdr:** Se ejecuta en una ventana emergente (`popup`) flotante y centrada sin alterar ni desplazar los paneles de trabajo del usuario.
* **Estado:** ✅ Desplegado, probado con el harness y activo en `herdr/config.toml`.
