package main

import (
	"bufio"
	"fmt"
	"os"
	"os/signal"
	"strings"
	"syscall"
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
		},
	},
	{
		Title: "󰘁  Sidebar (herdr-sidebar)",
		Color: cBlue,
		Items: []Item{
			{"1 / 2 / 3", "Explorer / Search / Git"},
			{"Ctrl+P", "Buscar archivo"},
			{"m", "Menú contextual"},
			{"s", "Settings de la sidebar"},
			{"sb-auto", "Auto-detectar monitor y adaptar ancho"},
			{"sb-ext", "Ancho angosto (22 cols) para monitor externo"},
			{"sb-lap", "Ancho normal (24 cols) para laptop"},
			{".", "Mostrar/ocultar archivos ocultos"},
			{"Enter", "Abrir / preview del archivo"},
		},
	},
	{
		Title: "󱞁  shiki  (notas y tareas)",
		Color: cGreen,
		Items: []Item{
			{"ctrl+b → o", "Abrir shiki"},
			{"↑↓ / ←→ / Enter", "Navegar cuadernos → notas → preview"},
			{"a", "Nueva nota (o cuaderno)"},
			{"i  /  Esc Esc", "Editar  /  guardar y salir"},
			{"/ al inicio", "Menú de bloques (checklist, tabla…)"},
			{"Ctrl+V (editor)", "Pegar captura como imagen"},
			{"espacio → t", "Todas las tareas"},
			{"espacio → g", "Buscar en todas las notas"},
			{"t", "Nota diaria de hoy"},
			{"H (preview)", "Historial git de la nota"},
			{"?", "Todos los atajos de shiki"},
		},
	},
	{
		Title: "󰉋  yazi  (explorador de archivos)",
		Color: cPeach,
		Items: []Item{
			{"y", "Abrir yazi (alias, queda en la carpeta)"},
			{"← / →", "Subir / entrar a la carpeta"},
			{"Enter", "Entrar y cerrar yazi"},
			{"o", "Abrir con $EDITOR"},
			{"n", "Crear archivo (/ = carpeta)"},
			{"r", "Renombrar"},
			{"Del", "Mover a la papelera"},
			{"q", "Salir"},
		},
	},
	{
		Title: "󰞷  Terminal  (zsh + herramientas)",
		Color: cTeal,
		Items: []Item{
			{"Ctrl+R", "Historial (atuin)"},
			{"Ctrl+T", "Buscar archivos (fzf)"},
			{"Alt+C", "Cambiar a carpeta (fzf)"},
			{"z <nombre>", "Ir a carpeta frecuente (zoxide)"},
			{"lg", "lazygit"},
			{"ld", "lazydocker"},
			{"sb", "Abrir sidebar (alias)"},
			{"brewup", "brew update+upgrade+cleanup+doctor"},
			{"brewout", "Ver actualizaciones pendientes"},
			{"Cmd+C", "Copiar selección (herdr/Ghostty)"},
			{"Cmd+V", "Pegar"},
			{"Cmd+Shift+,", "Recargar config de Ghostty"},
		},
	},
	{
		Title: "󰒍  SSH / Raspberry Pi (pi-host)",
		Color: cRed,
		Items: []Item{
			{"ctrl+b → s", "sshs → elegir pi-host"},
			{"ssh pi-host", "Conectar directo (192.0.2.10)"},
			{"http://192.0.2.10/panel", "DNS-blocker admin web"},
			{"dnsblock status", "Estado del bloqueo DNS"},
			{"dnsblock -g", "Actualizar gravity (listas)"},
			{"dnsblock -c", "Chronometer (stats en terminal)"},
			{"dnsblock restartdns", "Reiniciar DNS"},
			{"sudo dnsblock set-password <pw>", "Cambiar contraseña web"},
			{"df -h / && free -h", "Disco y RAM"},
			{"vcgencmd measure_temp", "Temperatura CPU"},
			{"sudo reboot", "Reiniciar la Pi"},
		},
	},
	{
		Title: "󰚩  Antigravity (agy) + agent-usage",
		Color: cYellow,
		Items: []Item{
			{"agy", "Antigravity sin confirmaciones (alias)"},
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
	// Limpiar pantalla al salir
	defer fmt.Print("\033[?25h\033[2J\033[H")

	// Capturar Ctrl+C
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigChan
		fmt.Print("\033[?25h\033[2J\033[H")
		os.Exit(0)
	}()

	scroll := 0
	filter := ""
	searchMode := false

	reader := bufio.NewReader(os.Stdin)

	draw := func() {
		fmt.Print("\033[?25l\033[2J\033[H")

		// Header
		fmt.Printf("%s%s┌──────────────────────────────────────────────────────────────┐%s\n", cBold, cMauve, cReset)
		title := "  󰌌  herdr cheatsheet"
		if filter != "" {
			title += fmt.Sprintf("  / %s%s%s", cYellow, filter, cMauve)
		}
		if searchMode {
			title += fmt.Sprintf("%s▌%s", cYellow, cMauve)
		}
		fmt.Printf("%s%s│%s %-58s %s%s│%s\n", cBold, cMauve, cReset, title, cBold, cMauve, cReset)
		fmt.Printf("%s%s└──────────────────────────────────────────────────────────────┘%s\n\n", cBold, cMauve, cReset)

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

			panel := fmt.Sprintf("%s%s╭─ %s %s────────────────────────────────────────%s\n", cBold, sec.Color, sec.Title, cSurface, cReset)
			for _, item := range matchingItems {
				panel += fmt.Sprintf("%s│  %s%-22s%s %s%s%s\n", cSurface, sec.Color+cBold, item.Key, cReset, cText, item.Desc, cReset)
			}
			panel += fmt.Sprintf("%s╰──────────────────────────────────────────────────────────────╯%s\n", cSurface, cReset)
			renderedPanels = append(renderedPanels, panel)
		}

		if len(renderedPanels) == 0 {
			fmt.Printf("   %s%sSin resultados para '%s'%s\n\n", cBold, cRed, filter, cReset)
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
		fmt.Printf("\n  %s%s↑↓ j/k%s %snavegar%s   %s%s/%s %sbuscar%s   %s%sq Esc%s %ssalir%s\n",
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

		if searchMode {
			if b == 27 || b == '\n' || b == '\r' { // Esc o Enter
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

		if b == '/' {
			searchMode = true
			draw()
		} else if b == 'q' || b == 'Q' || b == 27 { // Esc / q
			break
		} else if b == 'j' {
			scroll++
			draw()
		} else if b == 'k' {
			if scroll > 0 {
				scroll--
			}
			draw()
		} else if b == 'g' {
			scroll = 0
			draw()
		} else if b == 'G' {
			scroll = 100
			draw()
		}
	}
}
