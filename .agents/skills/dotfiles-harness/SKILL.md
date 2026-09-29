---
name: dotfiles-harness
description: Ejecuta la suite completa de pruebas, sintaxis TOML/YAML/JSON, verificación de atajos de herdr y compilación de herramientas Go para los dotfiles de macOS.
---

# Dotfiles Harness Runner Skill

Usa esta skill cada vez que realices una modificación en cualquier archivo de configuración de `dotfiles` o en las herramientas de `mac/tools/`.

## Instrucciones de Ejecución

1. Ejecuta el script de validación desde la raíz del repositorio de dotfiles:
   ```bash
   python3 harness/validate_configs.py
   ```

2. Analiza los resultados:
   - Si todo está en `[PASS]`, el cambio es seguro y libre de regresiones.
   - Si aparece algún `[FAIL]`, debes detenerte, leer el detalle del error y corregirlo antes de hacer commit o responder al usuario.

3. Para probar la compilación de `herdr-ctl` en Go:
   ```bash
   cd mac/tools/herdr-ctl && go test ./... && go build -o /dev/null .
   ```
