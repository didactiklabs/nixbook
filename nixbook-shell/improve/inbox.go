package main

import (
	"crypto/sha256"
	"encoding/hex"
	"path/filepath"
	"slices"
	"strings"
)

// An Item is something to fix: what the user reported (through an agent's
// report_problem or Settings), or a bug the shell's log or the desktop tools
// keep showing. The same key again counts up instead of adding an item.
type Item struct {
	ID    string `json:"id"`
	Key   string `json:"key"`
	Kind  string `json:"kind"` // user, qml, crash
	Text  string `json:"text"`
	Where string `json:"where,omitempty"` // a file or feature, when known
	// A QML warning's line, and the revision the shell printing it ran
	// (/etc/nixos/version): main may have moved since.
	Line int    `json:"line,omitempty"`
	Rev  string `json:"rev,omitempty"`
	// A CI item's failed run (its logs go to the session).
	Ref   string `json:"ref,omitempty"`
	Count int    `json:"count"`
	First int64  `json:"first"`
	Last  int64  `json:"last"`
	// new, working, pr (a PR is open), merged, skipped (not a bug, or not
	// enough to go on), ignored (skipped as harmless and unfixable: never
	// tried again), too_big (a feature or a refactor: a real session's
	// job), failed (its change never passed), dropped (by the user), gone
	// (a failed unit running again, CI green again before a fix).
	Status string `json:"status"`
	Note   string `json:"note,omitempty"` // why it was skipped, failed…
	PR     int    `json:"pr,omitempty"`
	Tried  int64  `json:"tried,omitempty"`
	// Count when last tried: tried again once it has grown since.
	TriedCount int `json:"triedCount,omitempty"`
}

type Inbox struct {
	Items []Item `json:"items"`
	// The shell's log and the tools' audit log are read from here on.
	LastCollect int64 `json:"lastCollect"`
}

const inboxMax = 60

func inboxPath() string { return filepath.Join(stateDir(), "inbox.json") }

// editInbox reads, changes and writes the inbox under its lock.
func editInbox(fn func(*Inbox) error) (Inbox, error) {
	unlock, err := lock("inbox.lock", true)
	if err != nil {
		return Inbox{}, err
	}
	defer unlock()
	var in Inbox
	if err := readJSON(inboxPath(), &in); err != nil {
		return in, err
	}
	if err := fn(&in); err != nil {
		return in, err
	}
	return in, writeJSON(inboxPath(), in)
}

func itemID(key string) string {
	sum := sha256.Sum256([]byte(key))
	return hex.EncodeToString(sum[:])[:8]
}

// add files an item, or counts it again (its status stays: a dropped one
// stays dropped; a merged one is still seen until the fix is deployed).
func (in *Inbox) add(kind, key, text, where string, times int, now int64) *Item {
	if times <= 0 {
		times = 1
	}
	if i := slices.IndexFunc(in.Items, func(it Item) bool { return it.Key == key }); i >= 0 {
		it := &in.Items[i]
		it.Count += times
		it.Last = now
		// The latest words: a failed unit's last log lines, CI's last run.
		if text != "" {
			it.Text = clip(text, 1500)
		}
		return it
	}
	in.Items = append(in.Items, Item{
		ID: itemID(key), Key: key, Kind: kind, Text: clip(text, 600),
		Where: where, Count: times, First: now, Last: now, Status: "new",
	})
	if len(in.Items) > inboxMax {
		// The oldest finished ones go first, then the oldest.
		slices.SortStableFunc(in.Items, func(a, b Item) int {
			fa, fb := a.Status != "new" && a.Status != "working" && a.Status != "pr",
				b.Status != "new" && b.Status != "working" && b.Status != "pr"
			if fa != fb {
				if fa {
					return -1
				}
				return 1
			}
			return int(a.Last - b.Last)
		})
		in.Items = in.Items[len(in.Items)-inboxMax:]
	}
	return &in.Items[len(in.Items)-1]
}

func (in *Inbox) find(id string) *Item {
	for i := range in.Items {
		if in.Items[i].ID == id {
			return &in.Items[i]
		}
	}
	return nil
}

// How often a bug must be seen before a run is spent on it: what the user
// reported is worth it at once.
var ripeCount = map[string]int{
	"user": 1, "qml": 3, "crash": 2,
	"service": 2, "log": 3, "deploy": 1, "warning": 2, "ci": 1, "coredump": 2,
}

const retryAfterMs = 7 * 24 * 3600 * 1000

// ripe: worth a run now. Tried before (skipped, failed), only a week later
// and seen more since.
func (it Item) ripe(now int64) bool {
	need, known := ripeCount[it.Kind]
	// What isn't nixbook's ("info") is never fixed unasked.
	if !known || it.Count < need {
		return false
	}
	switch it.Status {
	case "new":
		return true
	case "skipped", "failed":
		return now-it.Tried > retryAfterMs && it.Count >= it.TriedCount+ripeCount[it.Kind]
	}
	return false
}

// pick is the item to work on: the user's first, then the most seen.
func (in *Inbox) pick(now int64) *Item {
	var best *Item
	score := func(it *Item) int {
		s := it.Count
		if it.Kind == "user" {
			s += 1000
		}
		return s
	}
	for i := range in.Items {
		it := &in.Items[i]
		if it.ripe(now) && (best == nil || score(it) > score(best)) {
			best = it
		}
	}
	return best
}

func clip(s string, n int) string {
	s = strings.TrimSpace(s)
	if r := []rune(s); len(r) > n {
		return string(r[:n-1]) + "…"
	}
	return s
}
