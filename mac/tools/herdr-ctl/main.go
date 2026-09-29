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

type PaneLayoutResult struct {
	Type   string     `json:"type"`
	Layout LayoutData `json:"layout"`
}

type LayoutData struct {
	TabID string      `json:"tab_id"`
	Area  Rect        `json:"area"`
	Panes []LayoutPane `json:"panes"`
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

func getStatePath() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".local", "state", "herdr", "plugins", "herdr-sidebar", "state.json")
}

func callRPC(method string, params interface{}) (*RPCResponse, error) {
	conn, err := net.DialTimeout("unix", getSocketPath(), 2*time.Second)
	if err != nil {
		return nil, fmt.Errorf("error al conectar con socket herdr: %w", err)
	}
	defer conn.Close()

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

func parseSplitPath(splitID string) []bool {
	if splitID == "split_0_root" || splitID == "root" {
		return []bool{}
	}
	parts := strings.Split(splitID, "_")
	if len(parts) < 3 {
		return []bool{}
	}
	var path []bool
	for _, ch := range parts[2] {
		if ch == '0' {
			path = append(path, false)
		} else if ch == '1' {
			path = append(path, true)
		}
	}
	return path
}

func adaptSidebar(forceMode string) error {
	const widthLaptop = 24
	const widthExternal = 22
	const colsThreshold = 200

	// 1. Obtener lista de paneles
	resp, err := callRPC("pane.list", map[string]interface{}{})
	if err != nil {
		return err
	}

	var paneList PaneListResult
	if err := json.Unmarshal(resp.Result, &paneList); err != nil {
		return err
	}

	if len(paneList.Panes) == 0 {
		return fmt.Errorf("no se encontraron paneles activos")
	}

	// 2. Obtener dimensiones de la ventana usando el primer panel
	layoutResp, err := callRPC("pane.layout", map[string]interface{}{
		"pane_id": paneList.Panes[0].PaneID,
	})
	if err != nil {
		return err
	}

	var layoutResult PaneLayoutResult
	if err := json.Unmarshal(layoutResp.Result, &layoutResult); err != nil {
		return err
	}

	totalWidth := layoutResult.Layout.Area.Width
	isExternal := totalWidth > colsThreshold

	targetCols := widthLaptop
	modeDesc := fmt.Sprintf("pantalla Mac (%d cols)", totalWidth)

	if forceMode == "external" || (forceMode == "" && isExternal) {
		targetCols = widthExternal
		modeDesc = fmt.Sprintf("monitor Ultra-Wide (%d cols)", totalWidth)
	} else if forceMode == "laptop" {
		targetCols = widthLaptop
		modeDesc = "forzado laptop"
	}

	// 3. Persistir en state.json del plugin
	statePath := getStatePath()
	if stateData, err := os.ReadFile(statePath); err == nil {
		var stateMap map[string]interface{}
		if err := json.Unmarshal(stateData, &stateMap); err == nil {
			stateMap["sidebar_width"] = targetCols
			if updatedData, err := json.Marshal(stateMap); err == nil {
				_ = os.WriteFile(statePath, updatedData, 0644)
			}
		}
	}

	// 4. Buscar y ajustar TODOS los sidebars de todos los workspaces y pestañas
	seenTabs := make(map[string]bool)
	var sidebarPanes []*PaneInfo
	for i := range paneList.Panes {
		p := &paneList.Panes[i]
		if p.Label == "Sidebar" && !seenTabs[p.TabID] {
			seenTabs[p.TabID] = true
			sidebarPanes = append(sidebarPanes, p)
		}
	}

	adaptedCount := 0
	for _, sb := range sidebarPanes {
		lResp, err := callRPC("pane.layout", map[string]interface{}{
			"pane_id": sb.PaneID,
		})
		if err != nil {
			continue
		}
		var lRes PaneLayoutResult
		if err := json.Unmarshal(lResp.Result, &lRes); err != nil {
			continue
		}

		var innermostSplit *LayoutSplit
		for i := range lRes.Layout.Splits {
			sp := &lRes.Layout.Splits[i]
			if sp.Rect.X == 0 && sp.Direction == "right" {
				if innermostSplit == nil || sp.Rect.Width < innermostSplit.Rect.Width {
					innermostSplit = sp
				}
			}
		}

		if innermostSplit == nil {
			continue
		}

		splitPath := parseSplitPath(innermostSplit.ID)
		ratio := float64(targetCols) / float64(innermostSplit.Rect.Width)
		if ratio < 0.05 {
			ratio = 0.05
		}
		if ratio > 0.40 {
			ratio = 0.40
		}

		_, err = callRPC("layout.set_split_ratio", map[string]interface{}{
			"tab_id": sb.TabID,
			"path":   splitPath,
			"ratio":  ratio,
		})
		if err == nil {
			adaptedCount++
		}
	}

	msg := fmt.Sprintf("Sidebar ajustado a %d cols (%d barras) — %s", targetCols, adaptedCount, modeDesc)
	fmt.Println("✓ " + msg)
	notify("herdr-ctl", msg)
	return nil
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

	if focusedPane.Label == "Sidebar" {
		notify("herdr-ctl", "El sidebar no se puede mover de pestaña")
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

func main() {
	cmd := "adapt"
	if len(os.Args) > 1 {
		cmd = os.Args[1]
	}

	switch cmd {
	case "adapt":
		mode := ""
		if len(os.Args) > 2 {
			mode = os.Args[2]
		}
		if err := adaptSidebar(mode); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
	case "move-tab":
		target := "new"
		if len(os.Args) > 2 {
			target = os.Args[2]
		}
		if err := movePaneTab(target); err != nil {
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
	default:
		fmt.Printf("Uso: herdr-ctl [adapt|swap|move-tab|cheatsheet|status]\n")
	}
}
