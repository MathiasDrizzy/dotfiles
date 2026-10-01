package main

import (
	"os"
	"os/exec"
	"regexp"
	"strings"
	"testing"
)

const repoConfigPath = "../../config/herdr/config.toml"
const zshrcPath = "../../zshrc"

func mustRead(t *testing.T, path string) string {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("no pude leer %s: %v", path, err)
	}
	return string(b)
}

// fixtureKeymap usa el default congelado de herdr 0.9.3 y el config REAL del repo.
func fixtureKeymap(t *testing.T) Keymap {
	return buildKeymap(mustRead(t, "testdata/herdr-0.9.3-default.toml"), mustRead(t, repoConfigPath))
}

func TestParseDefaultKeys(t *testing.T) {
	d := parseDefaultKeys(mustRead(t, "testdata/herdr-0.9.3-default.toml"))
	want := map[string]string{
		"focus_pane_left":          "prefix+h",
		"open_notification_target": "prefix+o",
		"split_horizontal":         "prefix+minus",
		"detach":                   "prefix+q",
		"reload_config":            "prefix+shift+r",
		"switch_tab":               "prefix+1..9",
		"clear_pane":               "",
		"prefix":                   "ctrl+b",
	}
	for a, k := range want {
		if got, ok := d[a]; !ok || got != k {
			t.Errorf("default %s = %q (existe=%v), esperado %q", a, got, ok, k)
		}
	}
	// Ni los ejemplos comentados de [[keys.command]] ni claves sueltas deben colarse como acciones.
	for _, junk := range []string{"key", "type", "command", "width", "height", "tabs", "workspaces", "agents"} {
		if _, ok := d[junk]; ok {
			t.Errorf("%q no es una acción de herdr y se coló en los defaults", junk)
		}
	}
}

func TestRepoOverridesAndCommands(t *testing.T) {
	km := fixtureKeymap(t)
	if km.Effective["focus_pane_left"] != "prefix+left" {
		t.Errorf("focus_pane_left efectivo = %q, esperado prefix+left", km.Effective["focus_pane_left"])
	}
	if km.Defaults["focus_pane_left"] != "prefix+h" {
		t.Errorf("el default no debe cambiar: %q", km.Defaults["focus_pane_left"])
	}
	keys := map[string]bool{}
	for _, c := range km.Commands {
		keys[c.Key] = true
	}
	for _, k := range []string{"prefix+h", "prefix+t", "prefix+m", "prefix+f"} {
		if !keys[k] {
			t.Errorf("falta el comando %s en el config del repo", k)
		}
	}
}

// El cheatsheet NO se escribe a mano: cada atajo mostrado tiene que existir en el keymap.
func TestCheatsheetOnlyShowsRealShortcuts(t *testing.T) {
	km := fixtureKeymap(t)
	secs := buildSections(km)
	if bad := validateCheatsheet(secs, km); len(bad) > 0 {
		t.Fatalf("el cheatsheet muestra atajos inexistentes: %v", bad)
	}
	// Los atajos falsos históricos no pueden reaparecer: " % [ d no son atajos de herdr 0.9.3.
	for _, sec := range secs {
		for _, it := range sec.Items {
			for _, fake := range []string{`→ "`, `→ %`, `→ [`, `→ d `} {
				if strings.Contains(it.Key+" ", fake) {
					t.Errorf("atajo fantasma en el cheatsheet: %q", it.Key)
				}
			}
		}
	}
}

// Prueba del validador: si el cheatsheet mencionara un atajo inexistente, DEBE fallar.
func TestValidatorCatchesNonexistentShortcut(t *testing.T) {
	km := fixtureKeymap(t)
	secs := buildSections(km)
	secs[0].Items = append(secs[0].Items, Item{Key: "ctrl+b → d", Desc: "Detach (falso)"})
	bad := validateCheatsheet(secs, km)
	if len(bad) != 1 || !strings.Contains(bad[0], "ctrl+b → d") {
		t.Fatalf("el validador no detectó el atajo falso: %v", bad)
	}
}

// Lo que sí existe aparece con la tecla EFECTIVA, no la de fábrica.
func TestCheatsheetUsesEffectiveKeys(t *testing.T) {
	km := fixtureKeymap(t)
	var all []string
	for _, sec := range herdrSections(km) {
		for _, it := range sec.Items {
			all = append(all, it.Key+"|"+it.Desc)
		}
	}
	text := strings.Join(all, "\n")
	for _, want := range []string{
		"ctrl+b → ←|Foco al cuadro de la izquierda",
		"ctrl+b → h|cheatsheet",
		"ctrl+b → -|Dividir cuadro (split_horizontal)",
		"ctrl+b → q|Detach",
	} {
		if !strings.Contains(text, want) {
			t.Errorf("falta %q en el cheatsheet generado", want)
		}
	}
	if strings.Contains(text, "ctrl+b → H|") || strings.Contains(text, "ctrl+b → h|Foco") {
		t.Errorf("el foco ya no va por h: el cheatsheet usó la tecla de fábrica")
	}
}

// Las secciones escritas a mano son herramientas, no atajos de herdr.
func TestStaticSectionsHaveNoHerdrShortcutsAndAliasesExist(t *testing.T) {
	zsh := mustRead(t, zshrcPath)
	for _, sec := range staticSections {
		for _, it := range sec.Items {
			if strings.Contains(it.Key, "→") || strings.HasPrefix(strings.ToLower(it.Key), "ctrl+b") || strings.Contains(it.Key, "prefix") {
				t.Errorf("%q: un atajo de herdr no puede escribirse a mano", it.Key)
			}
			if it.Alias != "" && !regexp.MustCompile(`(?m)^alias `+regexp.QuoteMeta(it.Alias)+`=`).MatchString(zsh) {
				t.Errorf("el cheatsheet lista el alias %q y no existe en mac/zshrc", it.Alias)
			}
		}
	}
}

func TestNativeActionsExistInHerdr(t *testing.T) {
	km := fixtureKeymap(t)
	described := map[string]bool{}
	for _, na := range nativeActions {
		described[na.Action] = true
		if !km.knownAction(na.Action) {
			t.Errorf("nativeActions describe %q, que no existe en herdr 0.9.3", na.Action)
		}
	}
	for a, def := range km.Defaults {
		if !described[a] && !ignoredActions[a] {
			t.Errorf("herdr tiene la acción %q (%q) sin descripción ni exclusión explícita", a, def)
		}
	}
}

// C4: cada atajo del repo contra los defaults.
func TestRepoKeymapHasNoUnresolvedConflicts(t *testing.T) {
	km := fixtureKeymap(t)
	fs := km.Conflicts()
	for _, f := range fs {
		t.Logf("%-9s %s", f.Level, f.Msg)
	}
	if n := Unresolved(fs); n > 0 {
		t.Fatalf("%d conflictos o acciones inexistentes sin resolver en mac/config/herdr/config.toml", n)
	}
}

func TestConflictsDetectsCollisions(t *testing.T) {
	def := mustRead(t, "testdata/herdr-0.9.3-default.toml")
	cfg := `
[keys]
teleport_pane = "prefix+shift+left"

[[keys.command]]
key = "prefix+o"
type = "shell"
command = "true"
description = "pisa notificaciones"

[[keys.command]]
key = "prefix+z"
type = "shell"
command = "true"
description = "pisa zoom"

[[keys.command]]
key = "prefix+z"
type = "shell"
command = "true"
description = "duplicado"
`
	fs := buildKeymap(def, cfg).Conflicts()
	text := ""
	for _, f := range fs {
		text += f.Level + " " + f.Msg + "\n"
	}
	for _, want := range []string{
		"ERROR [keys] teleport_pane",
		"CONFLICTO prefix+o (pisa notificaciones) pisa a la acción nativa open_notification_target",
		"CONFLICTO prefix+z (pisa zoom) pisa a la acción nativa zoom",
		"CONFLICTO prefix+z lo usan dos comandos",
	} {
		if !strings.Contains(text, want) {
			t.Errorf("no se detectó %q\n--- hallazgos ---\n%s", want, text)
		}
	}
}

func TestPrefixShiftRIsDocumentedReplacement(t *testing.T) {
	text := ""
	for _, f := range fixtureKeymap(t).Conflicts() {
		text += f.Level + " " + f.Msg + "\n"
	}
	if !strings.Contains(text, "INFO prefix+shift+r") || !strings.Contains(text, "reload_config") {
		t.Errorf("prefix+shift+r debe quedar documentado como reemplazo de reload_config:\n%s", text)
	}
	if !strings.Contains(text, "prefix+h") || !strings.Contains(text, "focus_pane_left") {
		t.Errorf("prefix+h debe quedar documentado como tecla liberada por el remapeo de focus_pane_left:\n%s", text)
	}
}

// Contra el herdr instalado (se salta si no está): los defaults reales no deben haber cambiado de forma.
func TestLiveHerdrDefaultsMatchFixture(t *testing.T) {
	out, err := exec.Command(herdrBin(), "--default-config").Output()
	if err != nil {
		t.Skip("herdr no disponible:", err)
	}
	live := parseDefaultKeys(string(out))
	frozen := parseDefaultKeys(mustRead(t, "testdata/herdr-0.9.3-default.toml"))
	for a, k := range frozen {
		if live[a] != k {
			t.Errorf("herdr instalado: %s = %q, el fixture dice %q; revisa nativeActions y regenera testdata", a, live[a], k)
		}
	}
	for a := range live {
		if _, ok := frozen[a]; !ok {
			t.Errorf("herdr instalado tiene una acción nueva %q que el fixture no conoce", a)
		}
	}
}

// Si un comando del repo pisa una acción nativa, el cheatsheet solo muestra el comando que realmente corre.
func TestCheatsheetHidesShadowedNativeAction(t *testing.T) {
	km := fixtureKeymap(t)
	n := 0
	for _, sec := range herdrSections(km) {
		for _, it := range sec.Items {
			if it.Key == "ctrl+b → Shift+R" {
				n++
				if strings.Contains(it.Desc, "Recargar") {
					t.Errorf("Shift+R aparece como reload_config, pero el repo lo reasigna: %q", it.Desc)
				}
			}
		}
	}
	if n != 1 {
		t.Errorf("ctrl+b → Shift+R debe aparecer exactamente una vez, aparece %d", n)
	}
}
