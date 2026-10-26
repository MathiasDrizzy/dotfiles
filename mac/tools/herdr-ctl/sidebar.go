package main

// The herdr sidebar's own rows (config.toml [ui.sidebar.*]): the data behind the $model, $ctx, $limits and $sync
// tokens. `herdr-ctl statusline` is Claude Code's status line and reports each session's model, context and usage
// to its own pane; `herdr-ctl spaces-sync`, run by a launch agent every minute, reports each space's git and CI state
// and hands the newest usage to every agent (the 5-hour and weekly windows are the account's, not a session's).

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

// metadataSource names this tool's reports to herdr; a later report from it replaces its earlier tokens of the same name.
const metadataSource = "herdr-ctl"

// Every outside command has a limit: a herdr, git or gh that hangs (no network, a locked index) is stopped instead of
// keeping Claude's status line or the minute's pass waiting.
const (
	herdrTimeout = 2 * time.Second
	gitTimeout   = 5 * time.Second
	ghTimeout    = 15 * time.Second
)

// commandOutput runs a command in dir (the current folder when empty) and stops it at its limit.
func commandOutput(limit time.Duration, dir, name string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), limit)
	defer cancel()
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Dir = dir
	cmd.WaitDelay = time.Second
	var stderr strings.Builder
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if ctx.Err() != nil {
		return "", fmt.Errorf("%s took more than %v", name, limit)
	}
	if err != nil {
		return strings.TrimSpace(stderr.String()), err
	}
	return strings.TrimSpace(string(out)), nil
}

// limitsAlertPercent is where a usage window starts showing when it comes back.
const limitsAlertPercent = 75

// stateLabels rename herdr's agent states in the agents rows.
var stateLabels = []string{"working=trabajando", "blocked=te espera", "done=listo", "idle=libre"}

var spanishWeekdays = [...]string{"dom", "lun", "mar", "mié", "jue", "vie", "sáb"}

// Window is one usage window: how much of it is used and when it resets (Unix seconds).
type Window struct {
	Percent  float64 `json:"used_percentage"`
	ResetsAt int64   `json:"resets_at"`
}

// Limits are the subscription's two usage windows, and when they were read (Unix seconds).
type Limits struct {
	FiveHour Window `json:"five_hour"`
	Week     Window `json:"seven_day"`
	SeenAt   int64  `json:"seen_at"`
}

// Statusline is the part of Claude Code's status line payload the sidebar shows.
type Statusline struct {
	Model   string
	Context *float64
	Limits  *Limits
}

func parseStatusline(data []byte) (Statusline, error) {
	var raw struct {
		Model struct {
			DisplayName string `json:"display_name"`
		} `json:"model"`
		ContextWindow struct {
			UsedPercentage *float64 `json:"used_percentage"`
		} `json:"context_window"`
		RateLimits *struct {
			FiveHour *Window `json:"five_hour"`
			SevenDay *Window `json:"seven_day"`
		} `json:"rate_limits"`
	}
	if err := json.Unmarshal(data, &raw); err != nil {
		return Statusline{}, fmt.Errorf("status line payload: %w", err)
	}
	s := Statusline{Model: strings.ToLower(strings.TrimSpace(raw.Model.DisplayName)), Context: raw.ContextWindow.UsedPercentage}
	if r := raw.RateLimits; r != nil && r.FiveHour != nil && r.SevenDay != nil {
		s.Limits = &Limits{FiveHour: *r.FiveHour, Week: *r.SevenDay}
	}
	return s, nil
}

// paneTokens are the agent's own rows: its model, its context and, once Claude Code reports them, the usage windows.
func (s Statusline) paneTokens(now time.Time) map[string]string {
	tokens := map[string]string{}
	if s.Model != "" {
		tokens["model"] = s.Model
	}
	if s.Context != nil {
		tokens["ctx"] = fmt.Sprintf("ctx %d%%", int(math.Floor(*s.Context)))
	}
	if s.Limits != nil {
		tokens["limits"] = s.Limits.format(now)
	}
	return tokens
}

// text is what Claude Code shows in its own status line.
func (s Statusline) text(now time.Time) string {
	tokens := s.paneTokens(now)
	parts := []string{}
	for _, k := range []string{"model", "ctx", "limits"} {
		if v := tokens[k]; v != "" {
			parts = append(parts, v)
		}
	}
	return strings.Join(parts, " · ")
}

// format is "5h 51% · sem 61%"; a window at 75% or more adds when it comes back (the hour, or the weekday for the
// week), and a window whose reset time has passed is empty again.
func (l Limits) format(now time.Time) string {
	part := func(name string, w Window, when func(time.Time) string) string {
		percent := int(math.Floor(w.Percent))
		reset := time.Unix(w.ResetsAt, 0).In(now.Location())
		if w.ResetsAt > 0 && !reset.After(now) {
			percent = 0
		}
		text := fmt.Sprintf("%s %d%%", name, percent)
		if percent >= limitsAlertPercent {
			text += " →" + when(reset)
		}
		return text
	}
	hour := func(t time.Time) string { return t.Format("15:04") }
	day := func(t time.Time) string { return spanishWeekdays[t.Weekday()] }
	return part("5h", l.FiveHour, hour) + " · " + part("sem", l.Week, day)
}

func limitsCachePath() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".cache", "herdr-ctl", "limits.json")
}

func readLimits(path string) (Limits, bool) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Limits{}, false
	}
	var l Limits
	if err := json.Unmarshal(data, &l); err != nil {
		return Limits{}, false
	}
	return l, true
}

// saveLimits keeps the newest reading: sessions report at different times, and an idle one must not roll it back.
func saveLimits(path string, l Limits) error {
	if old, ok := readLimits(path); ok && old.SeenAt > l.SeenAt {
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	data, err := json.Marshal(l)
	if err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

func tokenArgs(tokens map[string]string) []string {
	keys := make([]string, 0, len(tokens))
	for k := range tokens {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	args := []string{}
	for _, k := range keys {
		args = append(args, "--token", k+"="+tokens[k])
	}
	return args
}

// paneReportArgs builds `herdr pane report-metadata`; herdr wants the pane id before the options.
func paneReportArgs(pane string, tokens map[string]string, labels []string) []string {
	args := append([]string{"pane", "report-metadata", pane, "--source", metadataSource}, tokenArgs(tokens)...)
	for _, l := range labels {
		args = append(args, "--state-label", l)
	}
	return args
}

func workspaceReportArgs(workspace string, tokens map[string]string, clear []string) []string {
	args := append([]string{"workspace", "report-metadata", workspace, "--source", metadataSource}, tokenArgs(tokens)...)
	for _, k := range clear {
		args = append(args, "--clear-token", k)
	}
	return args
}

func runHerdr(args []string) error {
	out, err := commandOutput(herdrTimeout, "", herdrBin(), args...)
	if err != nil {
		return fmt.Errorf("herdr %s: %s (%w)", strings.Join(args[:2], " "), out, err)
	}
	return nil
}

// runStatusline is `herdr-ctl statusline`: Claude Code's status line. It prints the line Claude Code shows and, inside
// a herdr pane, reports the same data to the pane. A failed report never breaks the line.
func runStatusline(in io.Reader, out io.Writer) error {
	data, err := io.ReadAll(in)
	if err != nil {
		return err
	}
	s, err := parseStatusline(data)
	if err != nil {
		return err
	}
	now := time.Now()
	if s.Limits != nil {
		s.Limits.SeenAt = now.Unix()
		_ = saveLimits(limitsCachePath(), *s.Limits)
	}
	if pane := os.Getenv("HERDR_PANE_ID"); pane != "" {
		_ = runHerdr(paneReportArgs(pane, s.paneTokens(now), stateLabels))
	}
	_, err = fmt.Fprintln(out, s.text(now))
	return err
}

// GitState is a space's repository: commits not pushed, files changed and the branch's last CI run.
type GitState struct {
	Ahead   int
	Changed int
	CI      string
}

func (g GitState) summary() string {
	git := []string{}
	if g.Ahead > 0 {
		git = append(git, fmt.Sprintf("↑%d", g.Ahead))
	}
	if g.Changed > 0 {
		git = append(git, fmt.Sprintf("✚%d", g.Changed))
	}
	parts := []string{}
	if len(git) > 0 {
		parts = append(parts, strings.Join(git, " "))
	}
	switch g.CI {
	case "":
	case "success":
		parts = append(parts, "CI ✓")
	case "failure", "cancelled", "timed_out", "startup_failure":
		parts = append(parts, "CI ✗")
	default:
		parts = append(parts, "CI …")
	}
	return strings.Join(parts, " · ")
}

// workspaceDirs maps each space to its repository: the folder of its agent's pane, or of its first pane.
func workspaceDirs(panes []PaneInfo) map[string]string {
	dirs := map[string]string{}
	// Agents first, so a space's agent wins over any other pane of it.
	for _, wantAgent := range []bool{true, false} {
		for _, p := range panes {
			if p.Cwd == "" || (p.Agent != "") != wantAgent {
				continue
			}
			if _, seen := dirs[p.WorkspaceID]; !seen {
				dirs[p.WorkspaceID] = p.Cwd
			}
		}
	}
	return dirs
}

func agentPanes(panes []PaneInfo) []string {
	ids := []string{}
	for _, p := range panes {
		if p.Agent != "" {
			ids = append(ids, p.PaneID)
		}
	}
	return ids
}

func gitOutput(dir string, args ...string) (string, error) {
	return commandOutput(gitTimeout, dir, "git", args...)
}

// readGitState asks git and gh about one repository; anything it cannot read is left empty, never guessed.
func readGitState(dir string) (GitState, bool) {
	if _, err := gitOutput(dir, "rev-parse", "--git-dir"); err != nil {
		return GitState{}, false
	}
	var g GitState
	base := "@{upstream}"
	if _, err := gitOutput(dir, "rev-parse", "--verify", "--quiet", base); err != nil {
		base = "origin/HEAD"
	}
	if n, err := gitOutput(dir, "rev-list", "--count", base+"..HEAD"); err == nil {
		g.Ahead, _ = strconv.Atoi(n)
	}
	if status, err := gitOutput(dir, "status", "--porcelain"); err == nil && status != "" {
		g.Changed = len(strings.Split(status, "\n"))
	}
	if branch, err := gitOutput(dir, "branch", "--show-current"); err == nil && branch != "" {
		if out, err := commandOutput(ghTimeout, dir, "gh", "run", "list", "--branch", branch, "--limit", "1", "--json",
			"status,conclusion"); err == nil {
			var runs []struct {
				Status     string `json:"status"`
				Conclusion string `json:"conclusion"`
			}
			if json.Unmarshal([]byte(out), &runs) == nil && len(runs) > 0 {
				g.CI = runs[0].Conclusion
				if runs[0].Status != "completed" {
					g.CI = runs[0].Status
				}
			}
		}
	}
	return g, true
}

// runSpacesSync is `herdr-ctl spaces-sync`: one pass over herdr's spaces and agents.
func runSpacesSync() error {
	resp, err := callRPC("pane.list", map[string]interface{}{})
	if err != nil {
		return err
	}
	var res PaneListResult
	if err := json.Unmarshal(resp.Result, &res); err != nil {
		return err
	}
	var failures []string
	for ws, dir := range workspaceDirs(res.Panes) {
		g, ok := readGitState(dir)
		if !ok {
			continue
		}
		summary := g.summary()
		args := workspaceReportArgs(ws, map[string]string{"sync": summary}, nil)
		if summary == "" {
			args = workspaceReportArgs(ws, nil, []string{"sync"})
		}
		if err := runHerdr(args); err != nil {
			failures = append(failures, err.Error())
		}
	}
	if l, ok := readLimits(limitsCachePath()); ok {
		text := l.format(time.Now())
		for _, pane := range agentPanes(res.Panes) {
			if err := runHerdr(paneReportArgs(pane, map[string]string{"limits": text}, nil)); err != nil {
				failures = append(failures, err.Error())
			}
		}
	}
	if len(failures) > 0 {
		return fmt.Errorf("%s", strings.Join(failures, "; "))
	}
	return nil
}
