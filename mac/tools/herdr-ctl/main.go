package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"path/filepath"
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

	var sidebarPane *PaneInfo
	var focusedPane *PaneInfo

	for i := range paneList.Panes {
		p := &paneList.Panes[i]
		if p.Label == "Sidebar" {
			sidebarPane = p
		}
		if p.Focused {
			focusedPane = p
		}
	}

	refPane := sidebarPane
	if refPane == nil {
		refPane = focusedPane
	}
	if refPane == nil && len(paneList.Panes) > 0 {
		refPane = &paneList.Panes[0]
	}

	if refPane == nil {
		return fmt.Errorf("no se encontraron paneles activos")
	}

	// 2. Obtener dimensiones de la ventana
	layoutResp, err := callRPC("pane.layout", map[string]interface{}{
		"tab_id":  refPane.TabID,
		"pane_id": refPane.PaneID,
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

	// 4. Si hay sidebar en pantalla, ajustar en vivo el split_ratio
	if sidebarPane != nil {
		splitWidth := totalWidth
		for _, sp := range layoutResult.Layout.Splits {
			if sp.Rect.X == 0 && sp.Direction == "right" {
				if sp.Rect.Width < splitWidth {
					splitWidth = sp.Rect.Width
				}
			}
		}

		ratio := float64(targetCols) / float64(splitWidth)
		if ratio < 0.08 {
			ratio = 0.08
		}
		if ratio > 0.40 {
			ratio = 0.40
		}

		_, err = callRPC("layout.set_split_ratio", map[string]interface{}{
			"tab_id": sidebarPane.TabID,
			"path":   []bool{false},
			"ratio":  ratio,
		})
		if err != nil {
			return err
		}
	}

	msg := fmt.Sprintf("Sidebar ajustado a %d cols — %s", targetCols, modeDesc)
	fmt.Println("✓ " + msg)
	notify("herdr-ctl", msg)
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
	case "status":
		resp, err := callRPC("pane.list", map[string]interface{}{})
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
		fmt.Printf("herdr server conectado. Paneles:\n%s\n", string(resp.Result))
	default:
		fmt.Printf("Uso: herdr-ctl [adapt|status] [auto|laptop|external]\n")
	}
}
