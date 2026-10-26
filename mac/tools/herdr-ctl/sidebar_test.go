package main

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
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

func TestAnIdleSessionsOldReadingNeverReplacesANewerOne(t *testing.T) {
	// An idle session refreshes its status line every 30 s with the usage of its own last response: 62% while the
	// working session already read 85%. Newer is the later window, or more of the same window, never the later run.
	window, nextWindow := int64(1793052000), int64(1793070000)
	fresh := Limits{FiveHour: Window{85, window}, Week: Window{65, 2}}
	stale := Limits{FiveHour: Window{62, window}, Week: Window{62, 2}}
	if got := newestLimits(stale, fresh); got != fresh {
		t.Fatalf("stale over fresh = %+v, want %+v", got, fresh)
	}
	if got := newestLimits(fresh, stale); got != fresh {
		t.Fatalf("fresh over stale = %+v, want %+v", got, fresh)
	}
	reset := Limits{FiveHour: Window{3, nextWindow}, Week: Window{66, 2}}
	if got := newestLimits(fresh, reset); got != reset {
		t.Fatalf("a new 5-hour window = %+v, want %+v", got, reset)
	}
	sameFive := Limits{FiveHour: Window{85, window}, Week: Window{70, 2}}
	if got := newestLimits(fresh, sameFive); got != sameFive {
		t.Fatalf("same 5-hour reading, more of the week = %+v, want %+v", got, sameFive)
	}
}

func TestLimitsCacheKeepsTheNewestReading(t *testing.T) {
	path := filepath.Join(t.TempDir(), "herdr-ctl", "limits.json")
	if _, ok := readLimits(path); ok {
		t.Fatal("an absent cache read as limits")
	}
	newer := Limits{FiveHour: Window{85, 1793052000}, Week: Window{65, 2}}
	older := Limits{FiveHour: Window{62, 1793052000}, Week: Window{62, 2}}
	if got, err := mergeLimits(path, newer); err != nil || got != newer {
		t.Fatalf("first reading = %+v %v", got, err)
	}
	if got, err := mergeLimits(path, older); err != nil || got != newer {
		t.Fatalf("an older reading after it = %+v %v, want the newer %+v kept and returned", got, err, newer)
	}
	if got, ok := readLimits(path); !ok || got != newer {
		t.Fatalf("cache = %+v %v, want %+v", got, ok, newer)
	}
	if err := os.WriteFile(path, []byte("{broken"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, ok := readLimits(path); ok {
		t.Fatal("a broken cache read as limits")
	}
	if got, err := mergeLimits(path, older); err != nil || got != older {
		t.Fatalf("a reading over a broken cache = %+v %v, want it stored", got, err)
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

func TestSpaceTokensDrawEveryRepositoryAsATree(t *testing.T) {
	// One repository is a tree of one, like a space that holds several: the same shape for every space.
	one := spaceTokens([]RepoState{{Name: "dotfiles", Branch: "feat/swift-bar", Git: GitState{Ahead: 1}}})
	if want := map[string]string{"repo1": "└ dotfiles", "repo1b": "\u2800 feat/swift-bar", "repo1s": "↑1"}; !reflect.DeepEqual(one, want) {
		t.Fatalf("one repository = %v, want %v", one, want)
	}
	// Each repository's name on its own line, its branch and state on the line below, inside the tree.
	two := spaceTokens([]RepoState{
		{Name: "lazymark", Branch: "main", Git: GitState{CI: "success"}},
		{Name: "lazyfinder", Branch: "main", Git: GitState{Changed: 2}},
	})
	want := map[string]string{
		"repo1": "├ lazymark", "repo1b": "│ main", "repo1s": "CI ✓",
		"repo2": "└ lazyfinder", "repo2b": "\u2800 main", "repo2s": "✚2",
	}
	if !reflect.DeepEqual(two, want) {
		t.Fatalf("two repositories = %v, want %v", two, want)
	}
	if got := len(spaceTokens(make([]RepoState, 5))); got > 3*maxSpaceRepos {
		t.Fatalf("five repositories gave %d tokens, past the %d rows the config has", got, 2*maxSpaceRepos)
	}
}

func TestSpaceTokensClearEveryRowTheyDoNotFill(t *testing.T) {
	got := spaceTokensToClear(map[string]string{"repo1b": "main", "repo1s": "CI ✓"})
	want := []string{"repo1", "repo2", "repo2b", "repo2s", "repo3", "repo3b", "repo3s", "sync"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("cleared = %v, want %v", got, want)
	}
}

func TestAgentsSayTheyHaveNoTokensWhileAWindowIsUsedUp(t *testing.T) {
	later := sidebarNow.Add(time.Hour).Unix()
	week := sidebarNow.Add(72 * time.Hour).Unix()
	exhausted := []string{"working=trabajando", "blocked=sin tokens", "done=sin tokens", "idle=sin tokens"}
	cases := []struct {
		name string
		l    *Limits
		want []string
	}{
		{"no usage known", nil, stateLabels},
		{"room left", &Limits{FiveHour: Window{88, later}, Week: Window{65, week}}, stateLabels},
		{"5 hours used up", &Limits{FiveHour: Window{100, later}, Week: Window{67, week}}, exhausted},
		{"the week used up", &Limits{FiveHour: Window{10, later}, Week: Window{100, week}}, exhausted},
		{"used up, but the window already reset", &Limits{FiveHour: Window{100, sidebarNow.Add(-time.Minute).Unix()}, Week: Window{67, week}}, stateLabels},
	}
	for _, c := range cases {
		if got := labelsFor(c.l, sidebarNow); !reflect.DeepEqual(got, c.want) {
			t.Errorf("%s: %v, want %v", c.name, got, c.want)
		}
	}
}

func TestTheWatcherNeverListensToWhatItReports(t *testing.T) {
	// herdr-ctl reports metadata, and a report raises workspace.metadata_updated and pane.updated: listening to those
	// would answer its own reports forever, the loop the lazyfinder sidebar once had.
	for _, e := range watchedEvents {
		if strings.Contains(e, "metadata") || strings.HasSuffix(e, ".updated") || strings.Contains(e, "output") ||
			strings.Contains(e, "scroll") || strings.Contains(e, "focused") || strings.Contains(e, "status_changed") {
			t.Errorf("the watcher listens to %q, which its own reports or every keystroke raise", e)
		}
	}
	for _, need := range []string{"tab.closed", "pane.closed", "pane.created", "workspace.closed"} {
		found := false
		for _, e := range watchedEvents {
			found = found || e == need
		}
		if !found {
			t.Errorf("the watcher misses %q: a closed tab would stay in the tree", need)
		}
	}
}

func TestReconnectsWaitLongerEachTime(t *testing.T) {
	want := []time.Duration{5 * time.Second, 10 * time.Second, 20 * time.Second, 40 * time.Second, time.Minute, time.Minute}
	got := []time.Duration{}
	for i := range want {
		got = append(got, reconnectDelay(i))
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("delays = %v, want %v", got, want)
	}
}

func TestCIIsAskedAtMostOncePerInterval(t *testing.T) {
	c := newCICache(time.Minute)
	calls := 0
	ask := func() string { calls++; return "success" }
	t0 := sidebarNow
	for _, at := range []time.Duration{0, 10 * time.Second, 59 * time.Second} {
		if got := c.get("/repo", "main", t0.Add(at), ask); got != "success" {
			t.Fatalf("ci = %q", got)
		}
	}
	if calls != 1 {
		t.Fatalf("gh asked %d times within a minute, want 1", calls)
	}
	c.get("/repo", "main", t0.Add(61*time.Second), ask)
	c.get("/repo", "feature", t0.Add(61*time.Second), ask)
	if calls != 3 {
		t.Fatalf("after a minute and for another branch: %d calls, want 3", calls)
	}
}

func TestADroppedConnectionNeverReconnectsInALoop(t *testing.T) {
	// herdr accepting the subscription and dropping it at once must still be waited out, longer each time.
	attempt := 0
	delays := []time.Duration{}
	for i := 0; i < 4; i++ {
		var d time.Duration
		d, attempt = afterDisconnect(attempt, 100*time.Millisecond)
		delays = append(delays, d)
	}
	if want := []time.Duration{5 * time.Second, 10 * time.Second, 20 * time.Second, 40 * time.Second}; !reflect.DeepEqual(delays, want) {
		t.Fatalf("quick drops waited %v, want %v", delays, want)
	}
	if d, next := afterDisconnect(attempt, 2*time.Minute); d != 5*time.Second || next != 1 {
		t.Fatalf("after a connection that held: wait %v next %d, want 5s and 1", d, next)
	}
	if watchCIInterval >= watchFullPass {
		t.Fatalf("CI is kept %v, not less than the %v between full passes: a pass would skip its refresh", watchCIInterval, watchFullPass)
	}
}

func TestReportsForClosedPanesAreForgotten(t *testing.T) {
	s := newSyncer(time.Minute)
	s.published = map[string]string{"ws w2": "a", "pane w2:p1": "b", "pane wF:p9": "c"}
	s.forgetExcept(map[string]bool{"ws w2": true, "pane w2:p1": true})
	if want := map[string]string{"ws w2": "a", "pane w2:p1": "b"}; !reflect.DeepEqual(s.published, want) {
		t.Fatalf("published = %v, want %v", s.published, want)
	}
}
