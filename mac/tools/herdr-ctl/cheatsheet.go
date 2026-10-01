package main

import (
	"bufio"
	"fmt"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"
	"unicode/utf8"

	"golang.org/x/term"
)

// Catppuccin Mocha ANSI 24-bit TrueColor
const (
	cReset    = "\033[0m"
	cBold     = "\033[1m"
	cDim      = "\033[2m"
	cMauve    = "\033[38;2;203;166;247m"
	cBlue     = "\033[38;2;137;180;250m"
	cGreen    = "\033[38;2;166;227;161m"
	cPeach    = "\033[38;2;250;179;135m"
	cTeal     = "\033[38;2;148;226;213m"
	cRed      = "\033[38;2;243;139;168m"
	cYellow   = "\033[38;2;249;226;175m"
	cLavender = "\033[38;2;180;190;254m"
	cText     = "\033[38;2;205;214;244m"
	cSubtext  = "\033[38;2;166;173;200m"
	cSurface  = "\033[38;2;69;71;90m"
)

type Item struct {
	Key   string
	Desc  string
	Alias string // si no está vacío, debe existir como alias en mac/zshrc (lo verifica un test)
}

type Section struct {
	Title string
	Color string
	Items []Item
}

// nativeAction describe una acción nativa de herdr. La tecla NO se escribe aquí:
// sale del keymap efectivo (herdr --default-config + config del repo).
type nativeAction struct {
	Action string
	Desc   string
	Group  string
}

const (
	grpPanes = "panes"
	grpTabs  = "tabs"
	grpWS    = "ws"
	grpOther = "other"
)

var nativeActions = []nativeAction{
	{"focus_pane_left", "Foco al cuadro de la izquierda", grpPanes},
	{"focus_pane_right", "Foco al cuadro de la derecha", grpPanes},
	{"focus_pane_up", "Foco al cuadro de arriba", grpPanes},
	{"focus_pane_down", "Foco al cuadro de abajo", grpPanes},
	{"cycle_pane_next", "Foco al cuadro siguiente", grpPanes},
	{"cycle_pane_previous", "Foco al cuadro anterior", grpPanes},
	{"last_pane", "Volver al cuadro anterior", grpPanes},
	{"split_vertical", "Dividir cuadro (split_vertical)", grpPanes},
	{"split_horizontal", "Dividir cuadro (split_horizontal)", grpPanes},
	{"close_pane", "Cerrar cuadro actual", grpPanes},
	{"zoom", "Zoom / restaurar cuadro", grpPanes},
	{"swap_pane_left", "Intercambiar cuadro con el de la izquierda", grpPanes},
	{"swap_pane_right", "Intercambiar cuadro con el de la derecha", grpPanes},
	{"swap_pane_up", "Intercambiar cuadro con el de arriba", grpPanes},
	{"swap_pane_down", "Intercambiar cuadro con el de abajo", grpPanes},
	{"resize_mode", "Modo redimensionar cuadros", grpPanes},
	{"resize_pane_left", "Redimensionar cuadro a la izquierda", grpPanes},
	{"resize_pane_right", "Redimensionar cuadro a la derecha", grpPanes},
	{"resize_pane_up", "Redimensionar cuadro hacia arriba", grpPanes},
	{"resize_pane_down", "Redimensionar cuadro hacia abajo", grpPanes},
	{"rename_pane", "Renombrar cuadro", grpPanes},
	{"edit_scrollback", "Editar el scrollback", grpPanes},
	{"clear_pane", "Limpiar cuadro", grpPanes},
	{"toggle_sidebar", "Mostrar / ocultar sidebar nativa", grpPanes},
	{"new_tab", "Nueva pestaña", grpTabs},
	{"rename_tab", "Renombrar pestaña", grpTabs},
	{"previous_tab", "Pestaña anterior", grpTabs},
	{"next_tab", "Pestaña siguiente", grpTabs},
	{"switch_tab", "Ir a la pestaña 1..9", grpTabs},
	{"close_tab", "Cerrar pestaña", grpTabs},
	{"move_tab_previous", "Mover pestaña hacia atrás", grpTabs},
	{"move_tab_next", "Mover pestaña hacia adelante", grpTabs},
	{"workspace_picker", "Selector de workspaces", grpWS},
	{"new_workspace", "Nuevo workspace", grpWS},
	{"rename_workspace", "Renombrar workspace", grpWS},
	{"close_workspace", "Cerrar workspace", grpWS},
	{"previous_workspace", "Workspace anterior", grpWS},
	{"next_workspace", "Workspace siguiente", grpWS},
	{"switch_workspace", "Ir al workspace 1..9", grpWS},
	{"new_worktree", "Nuevo worktree", grpWS},
	{"open_worktree", "Abrir worktree", grpWS},
	{"remove_worktree", "Quitar worktree", grpWS},
	{"previous_agent", "Agente anterior", grpWS},
	{"next_agent", "Agente siguiente", grpWS},
	{"focus_agent", "Foco al agente N", grpWS},
	{"goto", "Ir a… (goto)", grpWS},
	{"help", "Todos los atajos nativos de herdr", grpOther},
	{"settings", "Ajustes de herdr", grpOther},
	{"reload_config", "Recargar config.toml", grpOther},
	{"open_notification_target", "Abrir el destino de la notificación", grpOther},
	{"detach", "Detach: salir del cliente (los procesos siguen vivos)", grpOther},
}

// ignoredActions son acciones del keymap que el cheatsheet no lista a propósito:
// teclas locales de modos modales, no atajos con prefijo.
var ignoredActions = map[string]bool{
	"prefix": true, "remote_image_paste": true,
	"navigate_workspace_up": true, "navigate_workspace_down": true,
	"navigate_pane_left": true, "navigate_pane_down": true,
	"navigate_pane_up": true, "navigate_pane_right": true,
}

// staticSections son herramientas y comandos de shell: NO son atajos de herdr.
// Un test verifica que ningún ítem de aquí pretenda ser un atajo con prefijo.
var staticSections = []Section{
	{
		Title: "󰞷  Herramientas TUI",
		Color: cPeach,
		Items: []Item{
			{Key: "yazi (y)", Desc: "Gestor de archivos (Espacio: preview)"},
			{Key: "yazi: a", Desc: "Crear archivo (o carpeta con / al final)"},
			{Key: "yazi: r / Delete", Desc: "Renombrar / borrar archivo"},
			{Key: "lazygit (lg)", Desc: "Interfaz visual para Git", Alias: "lg"},
			{Key: "lazydocker (ld)", Desc: "Gestión de contenedores Docker", Alias: "ld"},
			{Key: "btop", Desc: "Monitor de recursos del sistema"},
			{Key: "micro <archivo>", Desc: "Editor rápido en terminal"},
			{Key: "sftp (termscp)", Desc: "Cliente SFTP / FTP / S3", Alias: "sftp"},
			{Key: "hosts (sshs)", Desc: "Selector visual de conexiones SSH", Alias: "hosts"},
			{Key: "glow <archivo>", Desc: "Renderizar Markdown en terminal"},
		},
	},
	{
		Title: "󰌌  Navegación en Terminal",
		Color: cTeal,
		Items: []Item{
			{Key: "z <carpeta>", Desc: "Saltar a directorio frecuente (zoxide)"},
			{Key: "Ctrl+R", Desc: "Historial interactivo (atuin)"},
			{Key: "Tab", Desc: "Menú fzf interactivo con previews"},
			{Key: "rg <texto>", Desc: "Buscar texto ultra rápido (ripgrep)"},
			{Key: "fd <nombre>", Desc: "Buscar archivos ultra rápido"},
			{Key: "bat <archivo>", Desc: "Cat con sintaxis y números de línea"},
			{Key: "mise ls", Desc: "Ver versiones activas de lenguajes"},
		},
	},
	{
		Title: "󰚩  Enjambre & Inter-Agentes",
		Color: cGreen,
		Items: []Item{
			{Key: "swarm / agents", Desc: "Estado del enjambre en tiempo real", Alias: "swarm"},
			{Key: "aprompt <ag> <msg>", Desc: "Enviar tarea/prompt a otro agente", Alias: "aprompt"},
			{Key: "aread <ag>", Desc: "Leer output del terminal de un agente", Alias: "aread"},
			{Key: "afocus <ag>", Desc: "Saltar y enfocar el panel del agente", Alias: "afocus"},
			{Key: "agy", Desc: "Antigravity CLI (agente de reserva)", Alias: "agy"},
			{Key: "claude", Desc: "Claude Code (alias)", Alias: "claude"},
		},
	},
	{
		Title: "󰊠  Ghostty",
		Color: cLavender,
		Items: []Item{
			{Key: "Cmd+T", Desc: "Nuevo tab"},
			{Key: "Cmd+N", Desc: "Nueva ventana"},
			{Key: "Cmd+D", Desc: "Split horizontal"},
			{Key: "Cmd+Shift+D", Desc: "Split vertical"},
			{Key: "Cmd+W", Desc: "Cerrar tab/pane"},
			{Key: "Cmd+Q", Desc: "Cerrar Ghostty (herdr sigue vivo)"},
			{Key: "Cmd+Shift+,", Desc: "Recargar configuración"},
			{Key: "Option Izq + Q", Desc: "Escribir @ (teclado latinoamericano)"},
		},
	},
}

// herdrSections genera las secciones de herdr desde el keymap efectivo.
func herdrSections(km Keymap) []Section {
	titles := map[string]string{
		grpPanes: "󰌌  herdr · cuadros",
		grpTabs:  "󰌌  herdr · pestañas",
		grpWS:    "󰌌  herdr · workspaces y agentes",
		grpOther: "󰌌  herdr · sesión",
	}
	// Un comando del repo en la misma tecla gana a la acción nativa (VERIFICADO: caso e del harness).
	shadowed := map[string]bool{}
	for _, c := range km.Commands {
		shadowed[c.Key] = true
	}
	var out []Section
	for _, g := range []string{grpPanes, grpTabs, grpWS, grpOther} {
		sec := Section{Title: titles[g], Color: cMauve}
		for _, na := range nativeActions {
			if na.Group != g {
				continue
			}
			if key := km.Effective[na.Action]; key != "" && !shadowed[key] {
				sec.Items = append(sec.Items, Item{Key: km.displayKey(key), Desc: na.Desc})
			}
		}
		if g == grpOther {
			for _, c := range km.Commands {
				d := c.Description
				if d == "" {
					d = c.Command
				}
				sec.Items = append(sec.Items, Item{Key: km.displayKey(c.Key), Desc: d})
			}
		}
		if len(sec.Items) > 0 {
			out = append(out, sec)
		}
	}
	return out
}

// buildSections junta lo generado (herdr) con las secciones de herramientas.
func buildSections(km Keymap) []Section {
	return append(herdrSections(km), staticSections...)
}

// cheatsheetSections carga el keymap real. Si no puede, lo dice en vez de inventar atajos.
func cheatsheetSections() []Section {
	km, err := loadKeymap()
	if err != nil {
		warn := Section{Title: "󰀦  herdr · keymap no disponible", Color: cRed,
			Items: []Item{{Key: "error", Desc: err.Error()}}}
		return append([]Section{warn}, staticSections...)
	}
	return buildSections(km)
}

// validateCheatsheet devuelve los atajos que el cheatsheet muestra pero no existen en el keymap.
func validateCheatsheet(secs []Section, km Keymap) []string {
	valid := map[string]bool{}
	for _, key := range km.Effective {
		for _, e := range expandKey(key) {
			if key != "" {
				valid[km.displayKey(e)] = true
			}
		}
		if strings.Contains(key, "1..9") {
			valid[km.displayKey(key)] = true
		}
	}
	for _, c := range km.Commands {
		valid[km.displayKey(c.Key)] = true
	}
	var bad []string
	for _, sec := range secs {
		for _, it := range sec.Items {
			if strings.Contains(it.Key, "→") || strings.HasPrefix(it.Key, km.Prefix) {
				if !valid[it.Key] {
					bad = append(bad, it.Key+" ("+it.Desc+")")
				}
			}
		}
	}
	return bad
}

func runeWidth(s string) int {
	return utf8.RuneCountInString(s)
}

func padRight(s string, targetCols int) string {
	w := runeWidth(s)
	if w >= targetCols {
		return s
	}
	return s + strings.Repeat(" ", targetCols-w)
}

func truncateRunes(s string, maxCols int) string {
	runes := []rune(s)
	if len(runes) <= maxCols {
		return s
	}
	if maxCols <= 1 {
		return "…"
	}
	return string(runes[:maxCols-1]) + "…"
}

func runCheatsheet() {
	fd := int(os.Stdin.Fd())
	oldState, err := term.MakeRaw(fd)
	if err == nil {
		defer term.Restore(fd, oldState)
	}

	restore := func() {
		fmt.Print("\033[?25h\033[2J\033[H")
		if oldState != nil {
			_ = term.Restore(fd, oldState)
		}
	}
	defer restore()

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigChan
		restore()
		os.Exit(0)
	}()

	sections := cheatsheetSections()
	scroll := 0
	filter := ""
	searchMode := false

	reader := bufio.NewReader(os.Stdin)

	draw := func() {
		termW, _, err := term.GetSize(int(os.Stdout.Fd()))
		if err != nil || termW < 60 {
			termW = 80
		}
		boxW := termW - 2
		if boxW > 78 {
			boxW = 78
		}
		if boxW < 60 {
			boxW = 60
		}

		// Limpiar pantalla y cursor a inicio
		fmt.Print("\033[?25l\033[2J\033[H")

		// Header en tarjeta
		fmt.Printf(" %s%s┌%s┐%s\r\n", cBold, cMauve, strings.Repeat("─", boxW-2), cReset)
		title := "  󰌌  herdr cheatsheet"
		if filter != "" {
			title += fmt.Sprintf("  / %s%s%s", cYellow, filter, cMauve)
		}
		if searchMode {
			title += fmt.Sprintf("%s▌%s", cYellow, cMauve)
		}
		innerHeaderWidth := boxW - 4
		fmt.Printf(" %s%s│%s %s %s%s│%s\r\n", cBold, cMauve, cReset, padRight(title, innerHeaderWidth), cBold, cMauve, cReset)
		fmt.Printf(" %s%s└%s┘%s\r\n\r\n", cBold, cMauve, strings.Repeat("─", boxW-2), cReset)

		// Filtrar y renderizar paneles
		var renderedPanels []string
		ft := strings.ToLower(filter)

		keyCols := 20
		descCols := boxW - keyCols - 7
		if descCols < 20 {
			descCols = 20
		}

		for _, sec := range sections {
			var matchingItems []Item
			for _, item := range sec.Items {
				if ft == "" || strings.Contains(strings.ToLower(item.Key), ft) || strings.Contains(strings.ToLower(item.Desc), ft) {
					matchingItems = append(matchingItems, item)
				}
			}

			if len(matchingItems) == 0 && ft != "" {
				continue
			}

			// Borde superior de tarjeta: ╭─ Title ──...──╮
			titleStr := fmt.Sprintf(" %s ", sec.Title)
			titleLen := runeWidth(titleStr)
			dashCount := boxW - 2 - 1 - titleLen
			if dashCount < 2 {
				dashCount = 2
			}
			panel := fmt.Sprintf(" %s%s╭─%s%s%s%s╮%s\r\n", cBold, sec.Color, titleStr, cSurface, strings.Repeat("─", dashCount), sec.Color+cBold, cReset)

			// Items dentro de la tarjeta con bordes alineados
			for _, item := range matchingItems {
				k := padRight(truncateRunes(item.Key, keyCols), keyCols)
				d := padRight(truncateRunes(item.Desc, descCols), descCols)
				panel += fmt.Sprintf(" %s│  %s%s%s %s%s%s  %s│%s\r\n",
					cSurface,
					sec.Color+cBold, k, cReset,
					cText, d, cReset,
					cSurface, cReset,
				)
			}

			// Borde inferior de tarjeta: ╰────────╯
			panel += fmt.Sprintf(" %s╰%s╯%s\r\n", cSurface, strings.Repeat("─", boxW-2), cReset)
			renderedPanels = append(renderedPanels, panel)
		}

		if len(renderedPanels) == 0 {
			fmt.Printf("   %s%sSin resultados para '%s'%s\r\n\r\n", cBold, cRed, filter, cReset)
		} else {
			if scroll >= len(renderedPanels) {
				scroll = len(renderedPanels) - 1
			}
			if scroll < 0 {
				scroll = 0
			}
			for i := scroll; i < len(renderedPanels); i++ {
				fmt.Print(renderedPanels[i])
			}
		}

		// Footer
		fmt.Printf("\r\n  %s%s↑↓ j/k%s %snavegar%s   %s%s/%s %sbuscar%s   %s%sq Esc%s %ssalir%s\r\n",
			cBold, cMauve, cReset, cSubtext, cReset,
			cBold, cBlue, cReset, cSubtext, cReset,
			cBold, cRed, cReset, cSubtext, cReset,
		)
	}

	draw()

	for {
		b, err := reader.ReadByte()
		if err != nil {
			break
		}

		// Escape key o secuencias ANSI
		if b == 27 {
			time.Sleep(15 * time.Millisecond)
			if reader.Buffered() > 0 {
				b2, err := reader.ReadByte()
				if err == nil && b2 == '[' {
					b3, err := reader.ReadByte()
					if err == nil {
						if b3 == 'A' { // Up arrow
							if scroll > 0 {
								scroll--
								draw()
							}
							continue
						} else if b3 == 'B' { // Down arrow
							scroll++
							draw()
							continue
						}
					}
				}
			}

			// Single ESC
			if searchMode {
				searchMode = false
				scroll = 0
				draw()
				continue
			} else {
				return
			}
		}

		if b == 3 { // Ctrl+C
			return
		}

		if searchMode {
			if b == '\r' || b == '\n' { // Enter
				searchMode = false
				scroll = 0
				draw()
			} else if b == 127 || b == 8 { // Backspace
				if len(filter) > 0 {
					filter = filter[:len(filter)-1]
					scroll = 0
					draw()
				}
			} else if b >= 32 && b <= 126 {
				filter += string(b)
				scroll = 0
				draw()
			}
			continue
		}

		// Modo navegación normal
		switch b {
		case 'q', 'Q':
			return
		case '/':
			searchMode = true
			draw()
		case 'j':
			scroll++
			draw()
		case 'k':
			if scroll > 0 {
				scroll--
			}
			draw()
		case 'g':
			scroll = 0
			draw()
		case 'G':
			scroll = 100
			draw()
		}
	}
}
