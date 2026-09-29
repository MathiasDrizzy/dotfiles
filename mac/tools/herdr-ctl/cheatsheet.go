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
	Key  string
	Desc string
}

type Section struct {
	Title string
	Color string
	Items []Item
}

var cheatsheetSections = []Section{
	{
		Title: "󰌌  herdr  (prefix = ctrl+b)",
		Color: cMauve,
		Items: []Item{
			{"ctrl+b → h", "Este cheatsheet interactivo"},
			{"ctrl+b → f", "Toggle sidebar (explorador)"},
			{"ctrl+b → m", "Auto-ajustar sidebar según pantalla"},
			{"ctrl+b → Shift+F", "Sidebar quick-open (Ctrl+P)"},
			{"ctrl+b → Shift+Q", "Settings de cuota (agent-usage)"},
			{"ctrl+b → Shift+R", "Refrescar cuotas de agentes"},
			{"ctrl+b → t", "termscp — explorador SFTP / FTP"},
			{"ctrl+b → s", "sshs — selector de conexiones SSH"},
			{"ctrl+b → o", "shiki — notas y tareas en Markdown"},
			{"ctrl+b → ?", "Todos los atajos nativos de herdr"},
			{"ctrl+b → q", "Salir de herdr (procesos siguen vivos)"},
			{"ctrl+b → c", "Nuevo tab"},
			{"ctrl+b → n / p", "Tab siguiente / anterior"},
			{"ctrl+b → [", "Modo scroll (q para salir)"},
			{"ctrl+b → d", "Detach sesión (herdr queda en background)"},
			{"ctrl+b → z", "Zoom / restaurar pane actual"},
			{"ctrl+b → \"", "Split horizontal"},
			{"ctrl+b → %", "Split vertical"},
			{"ctrl+b → x", "Cerrar pane actual"},
			{"ctrl+b → ↑↓←→", "Navegar entre panes"},
			{"ctrl+b → w", "Selector interactivo de workspaces"},
		},
	},
	{
		Title: "󰞷  Herramientas TUI",
		Color: cPeach,
		Items: []Item{
			{"yazi", "Gestor de archivos (Espacio: preview)"},
			{"lazygit", "Interfaz visual para Git"},
			{"lazydocker", "Gestión de contenedores Docker"},
			{"btop", "Monitor de recursos del sistema"},
			{"micro <archivo>", "Editor rápido en terminal"},
			{"termscp", "Cliente SFTP / FTP / S3"},
			{"sshs", "Selector visual de conexiones SSH"},
			{"shiki", "Notas + tareas + imágenes en Markdown"},
			{"glow <archivo>", "Renderizar Markdown en terminal"},
		},
	},
	{
		Title: "󰌌  Navegación en Terminal",
		Color: cTeal,
		Items: []Item{
			{"z <carpeta>", "Saltar a directorio frecuente (zoxide)"},
			{"Ctrl+R", "Historial interactivo sincronizado"},
			{"Tab", "Menú fzf interactivo con previews"},
			{"rg <texto>", "Buscar texto ultra rápido (ripgrep)"},
			{"fd <nombre>", "Buscar archivos ultra rápido"},
			{"bat <archivo>", "Cat con sintaxis y números de línea"},
			{"mise ls", "Ver versiones activas de lenguajes"},
		},
	},
	{
		Title: "󰚩  Antigravity & AI",
		Color: cGreen,
		Items: []Item{
			{"agy", "Lanzar Antigravity CLI"},
			{"claude", "Claude Code sin confirmaciones (alias)"},
			{"ctrl+b → Shift+Q", "Settings de cuota de Claude/Agy"},
			{"ctrl+b → Shift+R", "Refrescar cuotas"},
			{"⏱ 7d ↑47%", "Ventana · pace (↑ holgado / ↓ frena)"},
			{"Shift+Tab", "Ciclo de modo (normal / bypass)"},
			{"agy --resume", "Retomar sesión después de reinicio"},
			{"Ctrl+V", "Pegar imagen en el agente"},
		},
	},
	{
		Title: "󰊠  Ghostty",
		Color: cLavender,
		Items: []Item{
			{"Cmd+T", "Nuevo tab"},
			{"Cmd+N", "Nueva ventana"},
			{"Cmd+D", "Split horizontal"},
			{"Cmd+Shift+D", "Split vertical"},
			{"Cmd+W", "Cerrar tab/pane"},
			{"Cmd+Q", "Cerrar Ghostty (herdr sigue vivo)"},
			{"Cmd+Shift+,", "Recargar configuración"},
			{"Option Izq + Q", "Escribir @ (teclado latinoamericano)"},
		},
	},
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
		fmt.Printf(" %s%s│%s %s %s%s│%s\r\n", cBold, cMauve, cReset, padRight(title, innerHeaderWidth-1), cBold, cMauve, cReset)
		fmt.Printf(" %s%s└%s┘%s\r\n\r\n", cBold, cMauve, strings.Repeat("─", boxW-2), cReset)

		// Filtrar y renderizar paneles
		var renderedPanels []string
		ft := strings.ToLower(filter)

		keyCols := 20
		descCols := boxW - keyCols - 7
		if descCols < 20 {
			descCols = 20
		}

		for _, sec := range cheatsheetSections {
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
