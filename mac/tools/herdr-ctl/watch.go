package main

// `herdr-ctl spaces-watch`: the space and agent rows follow herdr's events instead of a clock. A tab or pane that
// opens, closes or moves syncs within half a second; once a minute a pass also refreshes CI and follows folders a
// shell moved to. Waiting on herdr's socket costs nothing.

import (
	"bufio"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"runtime"
	"sync"
	"syscall"
	"time"
)

// watchedEvents change which repositories a space holds. Never metadata or *.updated events: herdr-ctl's own reports
// raise those, and answering them would loop forever.
var watchedEvents = []string{
	"workspace.created", "workspace.closed", "workspace.moved",
	"worktree.created", "worktree.opened", "worktree.removed",
	"tab.created", "tab.closed", "tab.moved",
	"pane.created", "pane.closed", "pane.exited", "pane.moved", "pane.agent_detected",
	// Which agent is in front. Measured: none while nothing is touched, none from a report, three at once per switch.
	"pane.focused", "tab.focused", "workspace.focused",
}

// eventName reads the "event" of a line herdr sends on a subscription; empty for anything else.
func eventName(line []byte) string {
	var e struct {
		Event string `json:"event"`
	}
	if json.Unmarshal(line, &e) != nil {
		return ""
	}
	return e.Event
}

// isFocusEvent is a change of what is in front, which moves no pane: it only needs the light pass.
func isFocusEvent(name string) bool {
	return name == "pane_focused" || name == "tab_focused" || name == "workspace_focused"
}

const (
	watchSettle      = 400 * time.Millisecond // events come in bursts (a tab and its panes): one pass for the burst
	watchFocusSettle = 15 * time.Millisecond  // a switch raises three focus events at once: one light pass for them
	watchFullPass    = time.Minute            // CI, and shells that changed folder, between events
	watchCIInterval  = 55 * time.Second       // under the full pass, so each full pass refreshes CI
	watchHeld        = time.Minute            // a connection that lasted this long counts as working
)

// afterDisconnect is how long to wait after a connection ends, and the next attempt number. Every end waits, longer
// each time, so herdr dropping the subscription at once is never answered in a loop; only a connection that held for
// a minute starts the count again.
func afterDisconnect(attempt int, lived time.Duration) (time.Duration, int) {
	if lived >= watchHeld {
		attempt = 0
	}
	return reconnectDelay(attempt), attempt + 1
}

// reconnectDelay waits longer after each failed attempt, up to a minute: a stopped herdr is never asked in a loop.
func reconnectDelay(attempt int) time.Duration {
	d := 5 * time.Second
	for i := 0; i < attempt && d < time.Minute; i++ {
		d *= 2
	}
	if d > time.Minute {
		d = time.Minute
	}
	return d
}

// passRequests asks for full passes without ever blocking the asker: one request waits at most, and a request made
// while a pass runs is kept, so a tab that closes during the slow pass is still seen right after it.
type passRequests struct{ ch chan struct{} }

func newPassRequests() *passRequests { return &passRequests{ch: make(chan struct{}, 1)} }

func (r *passRequests) ask() {
	select {
	case r.ch <- struct{}{}:
	default:
	}
}

// ciCache keeps a branch's last CI for an interval, so events never make gh run more than once a minute.
type ciCache struct {
	mu       sync.Mutex
	interval time.Duration
	entries  map[string]ciEntry
}

type ciEntry struct {
	value string
	at    time.Time
}

func newCICache(interval time.Duration) *ciCache {
	return &ciCache{interval: interval, entries: map[string]ciEntry{}}
}

func (c *ciCache) get(dir, branch string, now time.Time, ask func() string) string {
	c.mu.Lock()
	defer c.mu.Unlock()
	key := dir + "\x00" + branch
	if e, ok := c.entries[key]; ok && now.Sub(e.at) < c.interval {
		return e.value
	}
	value := ask()
	c.entries[key] = ciEntry{value: value, at: now}
	return value
}

// subscribe opens a connection to herdr subscribed to watchedEvents; every line it sends after the answer is an event.
func subscribe() (net.Conn, *bufio.Reader, error) {
	conn, err := net.DialTimeout("unix", getSocketPath(), 2*time.Second)
	if err != nil {
		return nil, nil, err
	}
	subs := []map[string]string{}
	for _, e := range watchedEvents {
		subs = append(subs, map[string]string{"type": e})
	}
	req, _ := json.Marshal(RPCRequest{ID: "herdr-ctl-watch", Method: "events.subscribe",
		Params: map[string]interface{}{"subscriptions": subs}})
	if _, err := conn.Write(append(req, '\n')); err != nil {
		_ = conn.Close()
		return nil, nil, err
	}
	reader := bufio.NewReader(conn)
	_ = conn.SetReadDeadline(time.Now().Add(5 * time.Second))
	line, err := reader.ReadBytes('\n')
	if err != nil {
		_ = conn.Close()
		return nil, nil, err
	}
	var resp RPCResponse
	if json.Unmarshal(line, &resp) != nil || resp.Error != nil {
		_ = conn.Close()
		return nil, nil, fmt.Errorf("events.subscribe refused: %s", string(line))
	}
	_ = conn.SetReadDeadline(time.Time{})
	return conn, reader, nil
}

// runSpacesWatch never returns: it syncs on herdr's events and once a minute, and reconnects when herdr goes away.
// The full pass (git, gh: seconds at times) runs in a goroutine of its own, so a focus change is answered in
// milliseconds even while it runs.
func runSpacesWatch() {
	defer runtime.KeepAlive(watcherLock) // holds the single-instance lock for as long as the watcher runs
	s := newSyncer(watchCIInterval)
	events := make(chan struct{}, 1)
	focus := make(chan struct{}, 1)
	// A reconnect means herdr may have restarted and forgotten every report: they all go out again.
	reconnected := make(chan struct{}, 1)
	full := newPassRequests()
	go func() {
		for range full.ch {
			time.Sleep(watchSettle) // events come in bursts (a tab and its panes): one pass for the burst
			select {
			case <-full.ch:
			default:
			}
			if err := s.pass(time.Now()); err != nil {
				fmt.Fprintf(os.Stderr, "spaces-watch: %v\n", err)
			}
		}
	}()
	go func() {
		for attempt := 0; ; {
			var delay time.Duration
			conn, reader, err := subscribe()
			if err != nil {
				delay, attempt = afterDisconnect(attempt, 0)
				time.Sleep(delay)
				continue
			}
			connected := time.Now()
			select {
			case reconnected <- struct{}{}:
			default:
			}
			for {
				line, err := reader.ReadBytes('\n')
				if err != nil {
					break
				}
				channel := events
				if isFocusEvent(eventName(line)) {
					channel = focus
				}
				select {
				case channel <- struct{}{}:
				default:
				}
			}
			_ = conn.Close()
			delay, attempt = afterDisconnect(attempt, time.Since(connected))
			time.Sleep(delay)
		}
	}()
	tick := time.NewTicker(watchFullPass)
	defer tick.Stop()
	for {
		select {
		case <-reconnected:
			s.reset()
			lightPass(s)
			full.ask()
		case <-events:
			full.ask()
		case <-focus:
			time.Sleep(watchFocusSettle)
			select { // the rest of the same switch
			case <-focus:
			default:
			}
			lightPass(s)
		case <-tick.C:
			full.ask()
		}
	}
}

func lightPass(s *syncer) {
	if err := s.focusPass(); err != nil {
		fmt.Fprintf(os.Stderr, "spaces-watch: %v\n", err)
	}
}

// watcherLock keeps the lock file reachable for the life of the process: an *os.File closes its descriptor when the
// garbage collector finds it unreachable, and closing the descriptor releases the lock.
var watcherLock *os.File

// lockWatcher takes the watcher's single-instance lock. The kernel drops it with the process, so a crash never leaves
// a stale one behind.
func lockWatcher(path string) (*os.File, bool) {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, false
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return nil, false
	}
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		_ = f.Close()
		return nil, false
	}
	watcherLock = f
	return f, true
}
