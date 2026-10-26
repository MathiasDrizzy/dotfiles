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
	"sync"
	"time"
)

// watchedEvents change which repositories a space holds. Never metadata or *.updated events: herdr-ctl's own reports
// raise those, and answering them would loop forever.
var watchedEvents = []string{
	"workspace.created", "workspace.closed", "workspace.moved",
	"worktree.created", "worktree.opened", "worktree.removed",
	"tab.created", "tab.closed", "tab.moved",
	"pane.created", "pane.closed", "pane.exited", "pane.moved", "pane.agent_detected",
}

const (
	watchSettle     = 400 * time.Millisecond // events come in bursts (a tab and its panes): one pass for the burst
	watchFullPass   = time.Minute            // CI, and shells that changed folder, between events
	watchCIInterval = 55 * time.Second       // under the full pass, so each full pass refreshes CI
	watchHeld       = time.Minute            // a connection that lasted this long counts as working
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
func runSpacesWatch() {
	s := newSyncer(watchCIInterval)
	events := make(chan struct{}, 1)
	// A reconnect means herdr may have restarted and forgotten every report: they all go out again.
	reconnected := make(chan struct{}, 1)
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
				if _, err := reader.ReadBytes('\n'); err != nil {
					break
				}
				select {
				case events <- struct{}{}:
				default:
				}
			}
			_ = conn.Close()
			delay, attempt = afterDisconnect(attempt, time.Since(connected))
			time.Sleep(delay)
		}
	}()
	full := time.NewTicker(watchFullPass)
	defer full.Stop()
	pass := func() {
		if err := s.pass(time.Now()); err != nil {
			fmt.Fprintf(os.Stderr, "spaces-watch: %v\n", err)
		}
	}
	for {
		select {
		case <-reconnected:
			s.published = map[string]string{}
			pass()
		case <-events:
			time.Sleep(watchSettle)
			select { // events that came while settling are part of this pass
			case <-events:
			default:
			}
			pass()
		case <-full.C:
			pass()
		}
	}
}
