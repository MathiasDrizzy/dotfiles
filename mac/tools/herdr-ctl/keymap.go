package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// Keymap es el mapa de atajos efectivo de herdr: los defaults de
// `herdr --default-config` con los overrides y comandos del config del repo.
type Keymap struct {
	Prefix    string
	Defaults  map[string]string // acción -> tecla por defecto de herdr
	Overrides map[string]string // acción -> tecla fijada por el config del repo
	Effective map[string]string // acción -> tecla vigente ("" = sin atajo)
	Commands  []Command         // [[keys.command]] del config del repo
}

type Command struct {
	Key         string
	Type        string
	Command     string
	Description string
}

var (
	// `# accion = "valor"` (default) o `accion = "valor"` (override), con comentario final opcional.
	keyLineRe  = regexp.MustCompile(`^\s*(#\s*)?([a-z][a-z0-9_]*)\s*=\s*"([^"]*)"\s*(#.*)?$`)
	headerRe   = regexp.MustCompile(`^\s*\[`)
	tomlStrRe  = regexp.MustCompile(`^\s*([a-z_]+)\s*=\s*"((?:[^"\\]|\\.)*)"\s*(#.*)?$`)
	cmdExample = regexp.MustCompile(`^#\s*\[\[keys\.command\]\]`)
)

// parseDefaultKeys lee la sección [keys] de `herdr --default-config`, donde cada
// acción aparece comentada: `# focus_pane_left = "prefix+h"`.
func parseDefaultKeys(text string) map[string]string {
	out := map[string]string{}
	in := false
	sc := bufio.NewScanner(strings.NewReader(text))
	for sc.Scan() {
		line := sc.Text()
		if !in {
			if strings.TrimSpace(line) == "[keys]" {
				in = true
			}
			continue
		}
		if headerRe.MatchString(line) || cmdExample.MatchString(line) {
			break // fin de las acciones: sigue el ejemplo de [[keys.command]]
		}
		if m := keyLineRe.FindStringSubmatch(line); m != nil {
			out[m[2]] = m[3]
		}
	}
	return out
}

// parseRepoKeys lee [keys] (overrides) y los bloques [[keys.command]] del config del repo.
func parseRepoKeys(text string) (map[string]string, []Command) {
	overrides := map[string]string{}
	var cmds []Command
	section := ""
	var cur *Command
	flush := func() {
		if cur != nil {
			cmds = append(cmds, *cur)
			cur = nil
		}
	}
	sc := bufio.NewScanner(strings.NewReader(text))
	sc.Buffer(make([]byte, 1<<20), 1<<20) // el config tiene líneas muy largas
	for sc.Scan() {
		line := sc.Text()
		trim := strings.TrimSpace(line)
		if strings.HasPrefix(trim, "#") || trim == "" {
			continue
		}
		if strings.HasPrefix(trim, "[") {
			flush()
			section = strings.Trim(trim, "[] ")
			if trim == "[[keys.command]]" {
				cur = &Command{}
			}
			continue
		}
		m := tomlStrRe.FindStringSubmatch(line)
		if m == nil {
			continue
		}
		switch {
		case section == "keys":
			overrides[m[1]] = m[2]
		case section == "keys.command" && cur != nil:
			switch m[1] {
			case "key":
				cur.Key = m[2]
			case "type":
				cur.Type = m[2]
			case "command":
				cur.Command = m[2]
			case "description":
				cur.Description = m[2]
			}
		}
	}
	flush()
	return overrides, cmds
}

// undocumentedActions son acciones que herdr acepta aunque `herdr --default-config` no las liste.
// VERIFICADO con el caso d2 de scripts/harness-behavior.py: sin estas líneas en el config,
// prefix+shift+flechas deja de intercambiar cuadros. Si una versión futura las quita, d2 falla.
var undocumentedActions = map[string]bool{
	"swap_pane_left": true, "swap_pane_right": true, "swap_pane_up": true, "swap_pane_down": true,
}

func (k Keymap) knownAction(a string) bool {
	_, ok := k.Defaults[a]
	return ok || undocumentedActions[a]
}

func buildKeymap(defaultCfg, repoCfg string) Keymap {
	km := Keymap{Defaults: parseDefaultKeys(defaultCfg)}
	km.Overrides, km.Commands = parseRepoKeys(repoCfg)
	km.Effective = map[string]string{}
	for a, k := range km.Defaults {
		km.Effective[a] = k
	}
	for a, k := range km.Overrides {
		if km.knownAction(a) {
			km.Effective[a] = k
		}
	}
	km.Prefix = km.Effective["prefix"]
	if km.Prefix == "" {
		km.Prefix = "ctrl+b"
	}
	return km
}

// herdrBin devuelve el binario de herdr (HERDR_BIN_PATH lo fija el propio herdr).
func herdrBin() string {
	if p := os.Getenv("HERDR_BIN_PATH"); p != "" {
		return p
	}
	return "herdr"
}

func readDefaultConfig() (string, error) {
	out, err := exec.Command(herdrBin(), "--default-config").Output()
	if err != nil {
		return "", fmt.Errorf("no pude ejecutar `herdr --default-config`: %w", err)
	}
	return string(out), nil
}

// herdrConfigPath es el config que herdr está usando (HERDR_CONFIG_PATH o ~/.config/herdr/config.toml).
func herdrConfigPath() string {
	if p := os.Getenv("HERDR_CONFIG_PATH"); p != "" {
		return p
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".config", "herdr", "config.toml")
}

func loadKeymap() (Keymap, error) {
	def, err := readDefaultConfig()
	if err != nil {
		return Keymap{}, err
	}
	repo, err := os.ReadFile(herdrConfigPath())
	if err != nil {
		return Keymap{}, fmt.Errorf("no pude leer el config de herdr: %w", err)
	}
	return buildKeymap(def, string(repo)), nil
}

// expandKey convierte "prefix+1..9" en prefix+1 … prefix+9 para comparar colisiones.
func expandKey(k string) []string {
	if i := strings.Index(k, "1..9"); i >= 0 {
		var out []string
		for d := '1'; d <= '9'; d++ {
			out = append(out, k[:i]+string(d)+k[i+4:])
		}
		return out
	}
	return []string{k}
}

var keyNames = map[string]string{
	"left": "←", "right": "→", "up": "↑", "down": "↓",
	"minus": "-", "tab": "Tab", "esc": "Esc", "enter": "Enter", "space": "Espacio",
	"shift": "Shift", "alt": "Alt", "cmd": "Cmd", "super": "Super", "ctrl": "ctrl",
}

// displayKey: "prefix+shift+left" -> "ctrl+b → Shift+←".
func (k Keymap) displayKey(key string) string {
	parts := strings.Split(key, "+")
	hasPrefix := parts[0] == "prefix"
	if hasPrefix {
		parts = parts[1:]
	}
	shifted := false
	for i, p := range parts {
		switch {
		case keyNames[p] != "":
			parts[i] = keyNames[p]
			shifted = shifted || p == "shift"
		case len(p) == 1 && shifted:
			parts[i] = strings.ToUpper(p)
		}
	}
	s := strings.Join(parts, "+")
	if hasPrefix {
		return k.Prefix + " → " + s
	}
	return s
}

type Finding struct {
	Level string // OK, INFO, CONFLICTO, ERROR
	Msg   string
}

// intentionalReplacements documenta los atajos que el repo pisa a propósito.
// La clave es la tecla; el valor, por qué se acepta.
var intentionalReplacements = map[string]string{
	"prefix+shift+r": "reemplaza a reload_config por el refresco de cuotas de herdr-agent-usage; recarga con `herdr server reload-config` o mac/scripts/herdr-reload.sh",
}

// Conflicts compara cada atajo del repo contra los defaults y el keymap efectivo.
func (k Keymap) Conflicts() []Finding {
	var fs []Finding

	// 1. Overrides a acciones que esta versión de herdr no tiene: el atajo no hace nada.
	var names []string
	for a := range k.Overrides {
		names = append(names, a)
	}
	sort.Strings(names)
	for _, a := range names {
		if !k.knownAction(a) {
			fs = append(fs, Finding{"ERROR", fmt.Sprintf("[keys] %s = %q: la acción no existe en este herdr (atajo muerto)", a, k.Overrides[a])})
		}
	}

	// 2. Dos acciones nativas efectivas con la misma tecla.
	owner := map[string][]string{}
	for a, key := range k.Effective {
		if key == "" || a == "prefix" {
			continue
		}
		for _, e := range expandKey(key) {
			owner[e] = append(owner[e], a)
		}
	}
	var keys []string
	for key := range owner {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	for _, key := range keys {
		if as := owner[key]; len(as) > 1 {
			sort.Strings(as)
			fs = append(fs, Finding{"CONFLICTO", fmt.Sprintf("%s lo usan varias acciones nativas: %s", key, strings.Join(as, ", "))})
		}
	}

	// 3. Comandos del repo contra acciones nativas efectivas y entre sí.
	seen := map[string]string{}
	for _, c := range k.Commands {
		label := c.Description
		if label == "" {
			label = c.Command
		}
		if prev, dup := seen[c.Key]; dup {
			fs = append(fs, Finding{"CONFLICTO", fmt.Sprintf("%s lo usan dos comandos del repo: %q y %q", c.Key, prev, label)})
		}
		seen[c.Key] = label

		if as := owner[c.Key]; len(as) > 0 {
			if why, ok := intentionalReplacements[c.Key]; ok {
				fs = append(fs, Finding{"INFO", fmt.Sprintf("%s (%s) pisa a %s: reemplazo intencional, %s", c.Key, label, strings.Join(as, ", "), why)})
			} else {
				fs = append(fs, Finding{"CONFLICTO", fmt.Sprintf("%s (%s) pisa a la acción nativa %s", c.Key, label, strings.Join(as, ", "))})
			}
			continue
		}
		// Libre hoy, pero ocupado por un default que el repo remapeó.
		var freed []string
		for a, def := range k.Defaults {
			if def == c.Key && k.Effective[a] != def {
				freed = append(freed, fmt.Sprintf("%s (ahora %s)", a, k.Effective[a]))
			}
		}
		if len(freed) > 0 {
			sort.Strings(freed)
			fs = append(fs, Finding{"INFO", fmt.Sprintf("%s (%s) usa la tecla que por defecto era de %s: reemplazo intencional", c.Key, label, strings.Join(freed, ", "))})
		} else {
			fs = append(fs, Finding{"OK", fmt.Sprintf("%s (%s) libre", c.Key, label)})
		}
	}
	return fs
}

// Unresolved cuenta los hallazgos que rompen el chequeo.
func Unresolved(fs []Finding) int {
	n := 0
	for _, f := range fs {
		if f.Level == "CONFLICTO" || f.Level == "ERROR" {
			n++
		}
	}
	return n
}

func runKeysCheck() int {
	km, err := loadKeymap()
	if err != nil {
		fmt.Fprintln(os.Stderr, "keys-check:", err)
		return 2
	}
	fs := km.Conflicts()
	for _, f := range fs {
		fmt.Printf("%-9s %s\n", f.Level, f.Msg)
	}
	n := Unresolved(fs)
	fmt.Printf("keys-check: %d comandos del repo, %d overrides, %d sin resolver\n", len(km.Commands), len(km.Overrides), n)
	if n > 0 {
		return 1
	}
	return 0
}
