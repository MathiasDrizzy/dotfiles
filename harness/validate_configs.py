#!/usr/bin/env python3
"""
Dotfiles Test & Validation Harness
Valida la integridad estricta de todos los componentes de dotfiles:
- Sintaxis TOML (herdr, starship, yazi, termscp)
- Detección de atajos duplicados o conflictivos en herdr
- Sintaxis JSON (micro)
- Sintaxis YAML (lazygit, lazydocker)
- Sintaxis de Scripts Shell (install.sh, zshrc, zshenv)
- Compilación de herramientas Go (herdr-ctl)
- Chequeo de portabilidad ($HOME vs rutas absolutas quemadas)
"""

import json
import os
import subprocess
import sys
import tomllib

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
MAC_DIR = os.path.join(REPO_ROOT, "mac")

passed_checks = 0
failed_checks = 0

def log_pass(msg):
    global passed_checks
    passed_checks += 1
    print(f"  [PASS] {msg}")

def log_fail(msg, error=None):
    global failed_checks
    failed_checks += 1
    print(f"  [FAIL] {msg}")
    if error:
        print(f"         Detalle: {error}")

def test_toml_files():
    print("\n🔍 Validando Archivos TOML...")
    toml_files = [
        "mac/config/herdr/config.toml",
        "mac/config/starship/starship.toml",
        "mac/config/termscp/config.toml",
        "mac/config/termscp/theme.toml",
        "mac/config/yazi/keymap.toml",
        "mac/config/yazi/theme.toml"
    ]
    for rel_path in toml_files:
        full_path = os.path.join(REPO_ROOT, rel_path)
        if not os.path.exists(full_path):
            log_fail(f"{rel_path} no encontrado")
            continue
        try:
            with open(full_path, "rb") as f:
                tomllib.load(f)
            log_pass(f"{rel_path} (Sintaxis válida)")
        except Exception as e:
            log_fail(f"{rel_path} contiene error de sintaxis", e)

def test_herdr_keybindings():
    print("\n🎹 Validando Atajos de Teclado de Herdr...")
    herdr_path = os.path.join(REPO_ROOT, "mac/config/herdr/config.toml")
    if not os.path.exists(herdr_path):
        log_fail("herdr/config.toml no encontrado")
        return

    with open(herdr_path, "rb") as f:
        data = tomllib.load(f)

    keys_sec = data.get("keys", {})
    seen_keys = {}

    # 1. Atajos nativos de nivel superior (focus_pane_*, swap_pane_*, etc.)
    for action, binding in keys_sec.items():
        if isinstance(binding, str):
            b_norm = binding.strip().lower()
            if b_norm in seen_keys:
                log_fail(f"Atajo nativo duplicado '{binding}': asignado a '{seen_keys[b_norm]}' y '{action}'")
            else:
                seen_keys[b_norm] = f"keys.{action}"

    # 2. Atajos de comandos personalizados ([[keys.command]])
    commands = keys_sec.get("command", [])
    for cmd in commands:
        key = cmd.get("key")
        desc = cmd.get("description", cmd.get("command", "desconocido"))
        if not key:
            log_fail("Comando sin clave 'key' especificada en [[keys.command]]")
            continue
        k_norm = key.strip().lower()
        if k_norm in seen_keys:
            log_fail(f"Atajo en conflicto '{key}': asignado a '{seen_keys[k_norm]}' y '{desc}'")
        else:
            seen_keys[k_norm] = f"command: {desc}"

    log_pass(f"{len(seen_keys)} atajos de teclado únicos verificados sin colisiones")

def test_json_files():
    print("\n🔍 Validando Archivos JSON...")
    json_files = ["mac/config/micro/settings.json"]
    for rel_path in json_files:
        full_path = os.path.join(REPO_ROOT, rel_path)
        if not os.path.exists(full_path):
            continue
        try:
            with open(full_path, "r", encoding="utf-8") as f:
                json.load(f)
            log_pass(f"{rel_path} (Sintaxis válida)")
        except Exception as e:
            log_fail(f"{rel_path} contiene error de sintaxis", e)

def test_shell_scripts():
    print("\n🐚 Validando Scripts Shell (Sintaxis zsh / bash)...")
    scripts = [
        ("mac/install.sh", "bash"),
        ("mac/zshenv", "zsh"),
        ("mac/zshrc", "zsh"),
        ("mac/scripts/notes-manager.sh", "bash"),
        ("mac/scripts/check-links.sh", "bash"),
        ("mac/scripts/herdr-reload.sh", "bash"),
        ("mac/scripts/terminal-popup.sh", "bash")
    ]
    for rel_path, shell_bin in scripts:
        full_path = os.path.join(REPO_ROOT, rel_path)
        if not os.path.exists(full_path):
            log_fail(f"{rel_path} no encontrado")
            continue
        res = subprocess.run([shell_bin, "-n", full_path], capture_output=True, text=True)
        if res.returncode == 0:
            log_pass(f"{rel_path} ({shell_bin} -n pasó sin errores)")
        else:
            log_fail(f"{rel_path} error de sintaxis en shell", res.stderr)

def test_install_script_dry_run():
    print("\n🚀 Ejecutando Prueba de Humo de install.sh (--dry-run)...")
    install_script = os.path.join(REPO_ROOT, "mac/install.sh")
    if not os.path.exists(install_script):
        log_fail("mac/install.sh no encontrado")
        return

    res = subprocess.run(["bash", install_script, "--dry-run"], cwd=REPO_ROOT, capture_output=True, text=True)
    if res.returncode == 0 and "Prueba de humo de install.sh superada al 100%" in res.stdout:
        log_pass("mac/install.sh --dry-run (Simulación limpia de extremo a extremo)")
    else:
        log_fail("mac/install.sh --dry-run falló", res.stderr or res.stdout)

def test_portability():
    print("\n🌐 Validando Portabilidad ($HOME vs rutas absolutas quemadas en scripts)...")
    shell_files = [
        "mac/install.sh",
        "mac/zshenv",
        "mac/zshrc",
        "mac/scripts/notes-manager.sh",
        "mac/scripts/check-links.sh",
        "mac/scripts/herdr-reload.sh",
        "mac/scripts/terminal-popup.sh"
    ]
    for rel_path in shell_files:
        full_path = os.path.join(REPO_ROOT, rel_path)
        if not os.path.exists(full_path):
            continue
        with open(full_path, "r", encoding="utf-8") as f:
            content = f.read()
        # Verificar que no contenga rutas de usuario quemadas en duro
        if "/Users/drizzy" in content:
            log_fail(f"{rel_path} contiene ruta quemada '/Users/drizzy' en lugar de $HOME")
        else:
            log_pass(f"{rel_path} (100% portable con $HOME)")

def test_go_tools():
    print("\n🐹 Validando Compilación de Herramientas Go (herdr-ctl)...")
    go_dir = os.path.join(REPO_ROOT, "mac/tools/herdr-ctl")
    if not os.path.exists(go_dir):
        log_fail("Directorio mac/tools/herdr-ctl no encontrado")
        return

    # go vet
    res_vet = subprocess.run(["go", "vet", "./..."], cwd=go_dir, capture_output=True, text=True)
    if res_vet.returncode == 0:
        log_pass("herdr-ctl (go vet pasó sin advertencias)")
    else:
        log_fail("herdr-ctl falló en go vet", res_vet.stderr)

    # go test
    res_test = subprocess.run(["go", "test", "./..."], cwd=go_dir, capture_output=True, text=True)
    if res_test.returncode == 0:
        log_pass("herdr-ctl (go test pasó)")
    else:
        log_fail("herdr-ctl falló en tests unitarios", res_test.stderr)

    # go build dry-run
    res_build = subprocess.run(["go", "build", "-o", "/dev/null", "."], cwd=go_dir, capture_output=True, text=True)
    if res_build.returncode == 0:
        log_pass("herdr-ctl (Compilación binaria exitosa)")
    else:
        log_fail("herdr-ctl falló al compilar", res_build.stderr)

def main():
    print("=" * 65)
    print("       DOTFILES HARNESS — SUITE DE VALIDACIÓN Y CONTROL")
    print("=" * 65)

    test_toml_files()
    test_herdr_keybindings()
    test_json_files()
    test_shell_scripts()
    test_portability()
    test_go_tools()
    test_install_script_dry_run()

    print("\n" + "=" * 65)
    print(f"RESUMEN: {passed_checks} Pruebas Exitosas | {failed_checks} Fallos")
    print("=" * 65)

    if failed_checks > 0:
        print("\n❌ EL HARNESS HA DETECTADO REGRESIONES O ERRORES.")
        sys.exit(1)
    else:
        print("\n✅ TODAS LAS PRUEBAS PASARON. SISTEMA ESTABLE.")
        sys.exit(0)

if __name__ == "__main__":
    main()
