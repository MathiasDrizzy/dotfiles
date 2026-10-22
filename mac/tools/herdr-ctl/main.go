package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

type RPCRequest struct {
	ID     string      `json:"id"`
	Method string      `json:"method"`
	Params interface{} `json:"params"`
}

type RPCResponse struct {
	ID     string          `json:"id"`
	Result json.RawMessage `json:"result,omitempty"`
	Error  *RPCError       `json:"error,omitempty"`
}

type RPCError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

type PaneListResult struct {
	Type  string     `json:"type"`
	Panes []PaneInfo `json:"panes"`
}

type PaneInfo struct {
	PaneID  string                 `json:"pane_id"`
	TabID   string                 `json:"tab_id"`
	Label   string                 `json:"label"`
	Focused bool                   `json:"focused"`
	Tokens  map[string]interface{} `json:"tokens"`
}

type AgentListResult struct {
	Type   string      `json:"type"`
	Agents []AgentInfo `json:"agents"`
}

type AgentInfo struct {
	TerminalID  string                 `json:"terminal_id"`
	Name        string                 `json:"name"`
	Agent       string                 `json:"agent"`
	AgentStatus string                 `json:"agent_status"`
	PaneID      string                 `json:"pane_id"`
	TabID       string                 `json:"tab_id"`
	WorkspaceID string                 `json:"workspace_id"`
	Cwd         string                 `json:"cwd"`
	Focused     bool                   `json:"focused"`
	Tokens      map[string]interface{} `json:"tokens"`
}

type PaneLayoutResult struct {
	Type   string     `json:"type"`
	Layout LayoutData `json:"layout"`
}

type LayoutData struct {
	TabID  string        `json:"tab_id"`
	Area   Rect          `json:"area"`
	Panes  []LayoutPane  `json:"panes"`
	Splits []LayoutSplit `json:"splits"`
}

type Rect struct {
	X      int `json:"x"`
	Y      int `json:"y"`
	Width  int `json:"width"`
	Height int `json:"height"`
}

type LayoutPane struct {
	PaneID string `json:"pane_id"`
	Rect   Rect   `json:"rect"`
}

type LayoutSplit struct {
	ID        string  `json:"id"`
	Direction string  `json:"direction"`
	Ratio     float64 `json:"ratio"`
	Rect      Rect    `json:"rect"`
}

func getSocketPath() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".config", "herdr", "herdr.sock")
}

func callRPC(method string, params interface{}) (*RPCResponse, error) {
	conn, err := net.DialTimeout("unix", getSocketPath(), 2*time.Second)
	if err != nil {
		return nil, fmt.Errorf("error al conectar con socket herdr: %w", err)
	}
	defer func() { _ = conn.Close() }()

	req := RPCRequest{
		ID:     "herdr-ctl",
		Method: method,
		Params: params,
	}

	data, err := json.Marshal(req)
	if err != nil {
		return nil, err
	}

	data = append(data, '\n')
	if _, err := conn.Write(data); err != nil {
		return nil, err
	}

	reader := bufio.NewReader(conn)
	line, err := reader.ReadBytes('\n')
	if err != nil {
		return nil, err
	}

	var resp RPCResponse
	if err := json.Unmarshal(line, &resp); err != nil {
		return nil, err
	}

	if resp.Error != nil {
		return nil, fmt.Errorf("RPC error %d: %s", resp.Error.Code, resp.Error.Message)
	}

	return &resp, nil
}

func notify(title, message string) {
	params := map[string]string{
		"title":   title,
		"message": message,
	}
	_, _ = callRPC("notification.show", params)
}

func movePaneTab(mode string) error {
	resp, err := callRPC("pane.list", map[string]interface{}{})
	if err != nil {
		return err
	}
	var paneList PaneListResult
	if err := json.Unmarshal(resp.Result, &paneList); err != nil {
		return err
	}

	var focusedPane *PaneInfo
	for i := range paneList.Panes {
		if paneList.Panes[i].Focused {
			focusedPane = &paneList.Panes[i]
			break
		}
	}

	if focusedPane == nil {
		return fmt.Errorf("no hay cuadro enfocado")
	}

	if focusedPane.Label == "lazyfinder" {
		notify("herdr-ctl", "lazyfinder no se puede mover de pestaña")
		return nil
	}

	if mode == "new" {
		cmd := exec.Command("/opt/homebrew/bin/herdr", "pane", "move", "--new-tab", "--focus", focusedPane.PaneID)
		if out, err := cmd.CombinedOutput(); err != nil {
			return fmt.Errorf("error al mover cuadro a nueva pestaña: %s (%w)", string(out), err)
		}
		notify("herdr-ctl", "✓ Cuadro movido a nueva pestaña")
		return nil
	}

	respTab, err := callRPC("tab.list", map[string]interface{}{})
	if err != nil {
		return err
	}
	var tabList struct {
		Tabs []struct {
			TabID   string `json:"tab_id"`
			Number  int    `json:"number"`
			Focused bool   `json:"focused"`
		} `json:"tabs"`
	}
	if err := json.Unmarshal(respTab.Result, &tabList); err != nil {
		return err
	}

	if len(tabList.Tabs) <= 1 {
		cmd := exec.Command("/opt/homebrew/bin/herdr", "pane", "move", "--new-tab", "--focus", focusedPane.PaneID)
		if out, err := cmd.CombinedOutput(); err != nil {
			return fmt.Errorf("error al mover cuadro a nueva pestaña: %s (%w)", string(out), err)
		}
		notify("herdr-ctl", "✓ Cuadro movido a nueva pestaña")
		return nil
	}

	currIdx := -1
	for i, t := range tabList.Tabs {
		if t.TabID == focusedPane.TabID {
			currIdx = i
			break
		}
	}

	targetIdx := 0
	if currIdx != -1 {
		if mode == "next" {
			targetIdx = (currIdx + 1) % len(tabList.Tabs)
		} else { // "prev"
			targetIdx = (currIdx - 1 + len(tabList.Tabs)) % len(tabList.Tabs)
		}
	}

	targetTabID := tabList.Tabs[targetIdx].TabID
	cmd := exec.Command("/opt/homebrew/bin/herdr", "pane", "move", "--tab", targetTabID, "--focus", focusedPane.PaneID)
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("error al mover cuadro a pestaña: %s (%w)", string(out), err)
	}

	notify("herdr-ctl", fmt.Sprintf("✓ Cuadro movido a pestaña %d", tabList.Tabs[targetIdx].Number))
	return nil
}

func reloadConfig() error {
	cmd := exec.Command("/opt/homebrew/bin/herdr", "server", "reload-config")
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("error al recargar herdr config: %s (%w)", string(out), err)
	}
	fmt.Printf("✓ %s", string(out))
	notify("herdr-ctl", "✓ Configuración recargada en caliente")
	return nil
}

func listAgents() error {
	resp, err := callRPC("agent.list", map[string]interface{}{})
	if err != nil {
		return err
	}

	var res AgentListResult
	if err := json.Unmarshal(resp.Result, &res); err != nil {
		return err
	}

	fmt.Printf("\n %s%s┌────────────────────────────────────────────────────────────────────────┐%s\n", cBold, cMauve, cReset)
	fmt.Printf(" %s%s│  󰚩  ENJAMBRE DE AGENTES ACTIVOS (herdr.sock inter-agent bus)          │%s\n", cBold, cMauve, cReset)
	fmt.Printf(" %s%s└────────────────────────────────────────────────────────────────────────┘%s\n\n", cBold, cMauve, cReset)

	if len(res.Agents) == 0 {
		fmt.Printf("  %sNo hay agentes activos detectados en este momento.%s\n\n", cSubtext, cReset)
		return nil
	}

	fmt.Printf("  %s%-12s %-10s %-8s %-12s %-26s %s%s\n", cBold+cSubtext, "AGENTE", "ESTADO", "PANEL", "WORKSPACE", "MODELO", "TOPIC / TAREA", cReset)
	fmt.Printf("  %s%s%s\n", cSurface, strings.Repeat("─", 74), cReset)

	for _, a := range res.Agents {
		statusColor := cGreen
		switch a.AgentStatus {
		case "idle":
			statusColor = cTeal
		case "blocked":
			statusColor = cPeach
		case "error":
			statusColor = cRed
		}

		name := a.Name
		if name == "" {
			name = a.Agent
		}

		model := ""
		if m, ok := a.Tokens["quota_provider_model"].(string); ok {
			model = m
		}

		topic := ""
		if t, ok := a.Tokens["quota_topic"].(string); ok {
			topic = t
		}

		workspace := a.WorkspaceID
		if g, ok := a.Tokens["quota_group"].(string); ok && g != "" {
			workspace = g
		}

		fmt.Printf("  %s%-12s%s %s%-10s%s %-8s %-12s %-26s %s\n",
			cBold+cMauve, truncateRunes(name, 12), cReset,
			statusColor, truncateRunes(a.AgentStatus, 10), cReset,
			a.PaneID,
			truncateRunes(workspace, 12),
			truncateRunes(model, 26),
			truncateRunes(topic, 26),
		)
	}
	fmt.Println()
	return nil
}

func promptAgent(target, prompt string) error {
	if target == "" || prompt == "" {
		return fmt.Errorf("uso: herdr-ctl prompt <agente|pane_id> <mensaje>")
	}
	cmd := exec.Command("/opt/homebrew/bin/herdr", "agent", "prompt", target, prompt)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("error al enviar prompt a %s: %s (%w)", target, string(out), err)
	}
	fmt.Printf("✓ Mensaje entregado a [%s]: %s\n", target, prompt)
	notify("herdr-ctl", fmt.Sprintf("Mensaje enviado a agente %s", target))
	return nil
}

func readAgent(target string) error {
	if target == "" {
		return fmt.Errorf("uso: herdr-ctl read <agente|pane_id>")
	}
	cmd := exec.Command("/opt/homebrew/bin/herdr", "agent", "read", target)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("error al leer agente %s: %s (%w)", target, string(out), err)
	}
	fmt.Print(string(out))
	return nil
}

func focusAgent(target string) error {
	if target == "" {
		return fmt.Errorf("uso: herdr-ctl focus <agente|pane_id>")
	}
	cmd := exec.Command("/opt/homebrew/bin/herdr", "agent", "focus", target)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("error al enfocar agente %s: %s (%w)", target, string(out), err)
	}
	fmt.Printf("✓ Enfocado agente [%s]\n", target)
	return nil
}

func main() {
	cmd := "cheatsheet"
	if len(os.Args) > 1 {
		cmd = os.Args[1]
	}

	switch cmd {
	case "move-tab":
		target := "new"
		if len(os.Args) > 2 {
			target = os.Args[2]
		}
		if err := movePaneTab(target); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
	case "reload":
		if err := reloadConfig(); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
	case "agents", "swarm":
		if err := listAgents(); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
	case "prompt":
		if len(os.Args) < 4 {
			fmt.Fprintf(os.Stderr, "Uso: herdr-ctl prompt <agente|pane_id> <mensaje>\n")
			os.Exit(1)
		}
		target := os.Args[2]
		prompt := strings.Join(os.Args[3:], " ")
		if err := promptAgent(target, prompt); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
	case "read":
		if len(os.Args) < 3 {
			fmt.Fprintf(os.Stderr, "Uso: herdr-ctl read <agente|pane_id>\n")
			os.Exit(1)
		}
		target := os.Args[2]
		if err := readAgent(target); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
	case "focus":
		if len(os.Args) < 3 {
			fmt.Fprintf(os.Stderr, "Uso: herdr-ctl focus <agente|pane_id>\n")
			os.Exit(1)
		}
		target := os.Args[2]
		if err := focusAgent(target); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
	case "status":
		resp, err := callRPC("pane.list", map[string]interface{}{})
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
		fmt.Printf("herdr server conectado. Paneles:\n%s\n", string(resp.Result))
	case "cheatsheet", "help-tui":
		runCheatsheet()
	case "keys-check":
		os.Exit(runKeysCheck())
	default:
		fmt.Printf("Uso: herdr-ctl [move-tab|reload|swarm|prompt|read|focus|cheatsheet|keys-check|status]\n")
	}
}
