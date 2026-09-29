---
name: tui-notes-researcher
description: Guía de investigación, benchmarking y evaluación de aplicaciones TUI para gestión de notas, tareas y conocimiento en terminal para macOS.
---

# TUI Notes Researcher Skill

Usa esta skill para evaluar, comparar y seleccionar herramientas TUI de notas y gestión de tareas en el entorno terminal de Mathias.

## Criterios de Evaluación Obligatorios

1. **Rendimiento y Binario Nativo:**
   - Preferencia por herramientas escritas en **Rust** o **Go** (ej. `nb`, `zk`, `clin-rs`, `toney`).
   - Evitar herramientas pesadas en Node.js o Python con arranque lento salvo que ofrezcan una UX sobresaliente.

2. **Compatibilidad con herdr y Ghostty:**
   - Comprobar que no emitan secuencias ANSI de detección de color de fondo que rompan paneles multiplexados.
   - Respetar temas oscuros (Catppuccin Mocha).

3. **Formato de Notas:**
   - 100% Markdown estándar plano (`.md`).
   - Soporte para Git o sincronización en carpetas locales directas.
   - Posibilidad de abrir en editor externo (`micro` o Neovim).
