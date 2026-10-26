package main

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"time"
)

// 2026-10-26 17:30 in Santiago (UTC-3).
var sidebarNow = time.Date(2026, 10, 26, 17, 30, 0, 0, time.FixedZone("CLT", -3*3600))

// A status line payload as Claude Code sends it: model, context and the subscription's usage windows.
const statuslineFixture = `{
  "model": {"id": "claude-opus-5-5", "display_name": "Opus 5.5"},
  "context_window": {"used_percentage": 62.4, "context_window_size": 200000},
  "rate_limits": {
    "five_hour": {"used_percentage": 51, "resets_at": 1793052000},
    "seven_day": {"used_percentage": 61, "resets_at": 1793451600}
  }
}`

func TestStatuslineTokensAreTheSessionsOwnData(t *testing.T) {
	s, err := parseStatusline([]byte(statuslineFixture))
	if err != nil {
		t.Fatal(err)
	}
	got := s.paneTokens(sidebarNow)
	want := map[string]string{"model": "opus 5.5", "ctx": "ctx 62%", "limits": "5h 51% · sem 61%"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("tokens = %v, want %v", got, want)
	}
}

func TestStatuslineWithoutUsageLeavesTheLimitsOut(t *testing.T) {
	// API keys and the first moments of a session have no rate_limits: nothing is invented.
	s, err := parseStatusline([]byte(`{"model": {"display_name": "Sonnet 5.5"}, "context_window": {"used_percentage": 5}}`))
	if err != nil {
		t.Fatal(err)
	}
	got := s.paneTokens(sidebarNow)
	want := map[string]string{"model": "sonnet 5.5", "ctx": "ctx 5%"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("tokens = %v, want %v", got, want)
	}
	if s.Limits != nil {
		t.Fatalf("limits = %+v, want none", s.Limits)
	}
}

func TestStatuslineRejectsGarbage(t *testing.T) {
	if _, err := parseStatusline([]byte("not json")); err == nil {
		t.Fatal("garbage parsed")
	}
}

func TestLimitsShowTheResetOnlyWhenAWindowIsNearlyUsed(t *testing.T) {
	inTwoHours := sidebarNow.Add(2 * time.Hour).Unix()
	inFourDays := sidebarNow.Add(4 * 24 * time.Hour).Unix()
	cases := []struct {
		name string
		l    Limits
		want string
	}{
		{"both low", Limits{FiveHour: Window{51, inTwoHours}, Week: Window{61, inFourDays}}, "5h 51% · sem 61%"},
		{"5h at 75% shows when it comes back", Limits{FiveHour: Window{75, inTwoHours}, Week: Window{61, inFourDays}}, "5h 75% →19:30 · sem 61%"},
		{"week high shows the day", Limits{FiveHour: Window{10, inTwoHours}, Week: Window{90, inFourDays}}, "5h 10% · sem 90% →vie"},
		{"a window already reset is empty again", Limits{FiveHour: Window{98, sidebarNow.Add(-time.Minute).Unix()}, Week: Window{61, inFourDays}}, "5h 0% · sem 61%"},
		{"percentages are whole", Limits{FiveHour: Window{33.6, inTwoHours}, Week: Window{0.4, inFourDays}}, "5h 33% · sem 0%"},
	}
	for _, c := range cases {
		if got := c.l.format(sidebarNow); got != c.want {
			t.Errorf("%s: %q, want %q", c.name, got, c.want)
		}
	}
}

func TestStateLabelsAreSpanish(t *testing.T) {
	want := []string{"working=trabajando", "blocked=te espera", "done=listo", "idle=libre"}
	if !reflect.DeepEqual(stateLabels, want) {
		t.Fatalf("labels = %v, want %v", stateLabels, want)
	}
}

func TestPaneReportArgsPutThePaneFirst(t *testing.T) {
	// herdr reads `--source probe` as an unknown option unless the pane id comes first.
	got := paneReportArgs("w2:p2N", map[string]string{"model": "opus 5.5", "ctx": "ctx 62%"}, []string{"idle=libre"})
	want := []string{"pane", "report-metadata", "w2:p2N", "--source", metadataSource,
		"--token", "ctx=ctx 62%", "--token", "model=opus 5.5", "--state-label", "idle=libre"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("args = %q, want %q", got, want)
	}
}

func TestLimitsCacheKeepsTheNewestReading(t *testing.T) {
	path := filepath.Join(t.TempDir(), "herdr-ctl", "limits.json")
	if _, ok := readLimits(path); ok {
		t.Fatal("an absent cache read as limits")
	}
	older := Limits{FiveHour: Window{40, 1}, Week: Window{60, 2}, SeenAt: 100}
	newer := Limits{FiveHour: Window{51, 1}, Week: Window{61, 2}, SeenAt: 200}
	if err := saveLimits(path, newer); err != nil {
		t.Fatal(err)
	}
	if err := saveLimits(path, older); err != nil {
		t.Fatal(err)
	}
	got, ok := readLimits(path)
	if !ok || got != newer {
		t.Fatalf("cache = %+v %v, want the newer %+v", got, ok, newer)
	}
	if err := os.WriteFile(path, []byte("{broken"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, ok := readLimits(path); ok {
		t.Fatal("a broken cache read as limits")
	}
}

func TestSyncSummary(t *testing.T) {
	cases := []struct {
		name string
		g    GitState
		want string
	}{
		{"everything", GitState{Ahead: 2, Changed: 3, CI: "success"}, "↑2 ✚3 · CI ✓"},
		{"failed CI", GitState{CI: "failure"}, "CI ✗"},
		{"CI running", GitState{Ahead: 1, CI: "in_progress"}, "↑1 · CI …"},
		{"no CI runs", GitState{Changed: 4}, "✚4"},
		{"clean and pushed, no CI", GitState{}, ""},
		{"cancelled counts as failed", GitState{CI: "cancelled"}, "CI ✗"},
	}
	for _, c := range cases {
		if got := c.g.summary(); got != c.want {
			t.Errorf("%s: %q, want %q", c.name, got, c.want)
		}
	}
}

func TestAgentPanesAreThePanesRunningAnAgent(t *testing.T) {
	panes := []PaneInfo{
		{PaneID: "w2:p46", WorkspaceID: "w2", Cwd: "/repo/other"},
		{PaneID: "w2:p2N", WorkspaceID: "w2", Agent: "claude", Cwd: "/repo/dotfiles"},
	}
	if agents := agentPanes(panes); !reflect.DeepEqual(agents, []string{"w2:p2N"}) {
		t.Fatalf("agent panes = %v", agents)
	}
}

func TestAHungCommandIsStoppedAtItsLimit(t *testing.T) {
	// gh or git waiting on the network must never keep spaces-sync, or Claude's status line, running.
	start := time.Now()
	_, err := commandOutput(200*time.Millisecond, "", "sleep", "5")
	if err == nil {
		t.Fatal("a command past its limit succeeded")
	}
	if took := time.Since(start); took > 2*time.Second {
		t.Fatalf("the hung command ran %v, past its 200ms limit", took)
	}
	out, err := commandOutput(time.Second, t.TempDir(), "pwd")
	if err != nil || out == "" {
		t.Fatalf("a quick command failed: %q %v", out, err)
	}
}

func TestASpaceListsEachOfItsRepositoriesOnce(t *testing.T) {
	panes := []PaneInfo{
		{WorkspaceID: "wF", Cwd: "/p/lazyfinder"},
		{WorkspaceID: "wF", Agent: "claude", Cwd: "/p/lazymark/docs"},
		{WorkspaceID: "wF", Agent: "claude", Cwd: "/p/lazymark"},
		{WorkspaceID: "w2", Cwd: ""},
	}
	root := map[string]string{"/p/lazyfinder": "/p/lazyfinder", "/p/lazymark/docs": "/p/lazymark", "/p/lazymark": "/p/lazymark"}
	got := workspaceRepos(panes, func(dir string) (string, bool) { r, ok := root[dir]; return r, ok })
	want := map[string][]string{"wF": {"/p/lazymark", "/p/lazyfinder"}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("repos = %v, want %v (agents' repositories first, each once)", got, want)
	}
}

func TestSpaceTokensDrawATreeOnlyForSeveralRepositories(t *testing.T) {
	one := spaceTokens([]RepoState{{Name: "dotfiles", Branch: "feat/swift-bar", Git: GitState{Ahead: 1}}})
	if want := map[string]string{"repo1": "feat/swift-bar", "repo1s": "↑1"}; !reflect.DeepEqual(one, want) {
		t.Fatalf("one repository = %v, want %v", one, want)
	}
	two := spaceTokens([]RepoState{
		{Name: "lazymark", Branch: "main", Git: GitState{CI: "success"}},
		{Name: "lazyfinder", Branch: "main", Git: GitState{Changed: 2}},
	})
	want := map[string]string{"repo1": "├ lazymark · main", "repo1s": "CI ✓", "repo2": "└ lazyfinder · main", "repo2s": "✚2"}
	if !reflect.DeepEqual(two, want) {
		t.Fatalf("two repositories = %v, want %v", two, want)
	}
	if got := len(spaceTokens(make([]RepoState, 5))); got > 2*maxSpaceRepos {
		t.Fatalf("five repositories gave %d tokens, past the %d rows the config has", got, maxSpaceRepos)
	}
}

func TestSpaceTokensClearEveryRowTheyDoNotFill(t *testing.T) {
	got := spaceTokensToClear(map[string]string{"repo1": "main", "repo1s": "CI ✓"})
	want := []string{"repo2", "repo2s", "repo3", "repo3s", "sync"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("cleared = %v, want %v", got, want)
	}
}
