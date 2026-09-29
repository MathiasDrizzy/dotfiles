package main

import (
	"bufio"
	"fmt"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

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
			{"ctrl+b → h", "Este cheatsheet"},
			{"ctrl+b → f", "Toggle sidebar (explorador)"},
			{"ctrl+b → m", "Sidebar auto-adapt (laptop ↔ monitor con herdr-ctl)"},
			{"ctrl+b → Shift+F", "Sidebar quick-open (Ctrl+P)"},
			{"ctrl+b → Shift+Q", "Settings de cuota (agent-usage)"},
			{"ctrl+b → Shift+R", "Refrescar cuotas"},
			{"ctrl+b → t", "termscp — SFTP/FTP (popup 90%)"},
			{"ctrl+b → s", "sshs — elegir servidor SSH"},
			{"ctrl+b → o", "shiki — notas y tareas"},
			{"ctrl+b → ?", "Todos los atajos de herdr"},
			{"ctrl+b → q", "Salir de herdr (todo sigue vivo)"},
			{"ctrl+b → c", "Nuevo tab"},
			{"ctrl+b → n / p", "Tab siguiente / anterior"},
			{"ctrl+b → [", "Modo scroll (q para salir)"},
			{"ctrl+b → d", "Detach (herdr queda vivo)"},
			{"ctrl+b → z", "Zoom pane actual"},
			{"ctrl+b → \"", "Split horizontal"},
			{"ctrl+b → %", "Split vertical"},
			{"ctrl+b → x", "Cerrar pane actual"},
			{"ctrl+b → ↑↓←→", "Moverse entre panes"},
			{"ctrl+b → w", "Lista interactiva de workspaces"},
		},
	},
	{
		Title: "󰞷  Herramientas TUI",
		Color: cPeach,
		Items: []Item{
			{"yazi", "Gestor de archivos (espacio para preview)"},
			{"lazygit", "Interfaz visual de Git"},
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
			{"Ctrl+R", "Historial sincronizado (atuin / fzf)"},
			{"Tab", "Menú fzf interactivo con previews"},
			{"rg <texto>", "Buscar texto ultra rápido (ripgrep)"},
			{"fd <nombre>", "Buscar archivos ultra rápido"},
			{"bat <archivo>", "Cat con colores y números de línea"},
			{"mise ls", "Ver versiones activas de lenguajes"},
		},
	},
	{
		Title: "󰚩  Antigravity & AI",
		Color: cGreen,
		Items: []Item{
			{"agy", "Lanzar Antigravity CLI"},
			{"claude", "Claude Code sin confirmaciones (alias)"},
			{"ctrl+b → Shift+Q", "Settings de cuota"},
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
			{"Cmd+Shift+,", "Recargar config"},
			{"Option Izq + Q", "Escribir @ (teclado latinoamericano)"},
		},
	},
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
		// Hide cursor, clear screen, cursor to home
		fmt.Print("\033[?25l\033[2J\033[H")

		// Header
		fmt.Printf("%s%s┌──────────────────────────────────────────────────────────────┐%s\r\n", cBold, cMauve, cReset)
		title := "  󰌌  herdr cheatsheet"
		if filter != "" {
			title += fmt.Sprintf("  / %s%s%s", cYellow, filter, cMauve)
		}
		if searchMode {
			title += fmt.Sprintf("%s▌%s", cYellow, cMauve)
		}
		fmt.Printf("%s%s│%s %-58s %s%s│%s\r\n", cBold, cMauve, cReset, title, cBold, cMauve, cReset)
		fmt.Printf("%s%s└──────────────────────────────────────────────────────────────┘%s\r\n\r\n", cBold, cMauve, cReset)

		// Filtrar y renderizar paneles
		var renderedPanels []string
		ft := strings.ToLower(filter)

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

			panel := fmt.Sprintf("%s%s╭─ %s %s────────────────────────────────────────%s\r\n", cBold, sec.Color, sec.Title, cSurface, cReset)
			for _, item := range matchingItems {
				panel += fmt.Sprintf("%s│  %s%-22s%s %s%s%s\r\n", cSurface, sec.Color+cBold, item.Key, cReset, cText, item.Desc, cReset)
			}
			panel += fmt.Sprintf("%s╰──────────────────────────────────────────────────────────────╯%s\r\n", cSurface, cReset)
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

		// Escape key or ANSI escape sequences
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

		// Normal navigation mode
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
