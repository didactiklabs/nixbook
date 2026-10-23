package main

import (
	"cmp"
	"crypto/sha256"
	"encoding/hex"
	"path/filepath"
	"slices"
	"strings"
)

// An Item is something to fix: what the user reported (through an agent's
// report_problem or Settings), or a bug the shell's log or the desktop tools
// keep showing; or a feature to build (kind feature: what the user asked
// for through an agent's request_feature or Settings, or a fix found too
// big for one). The same key again counts up instead of adding an item.
type Item struct {
	ID    string `json:"id"`
	Key   string `json:"key"`
	Kind  string `json:"kind"` // user, qml, crash…, feature
	Text  string `json:"text"`
	Where string `json:"where,omitempty"` // a file or feature, when known
	// A QML warning's line, and the revision the shell printing it ran
	// (/etc/nixos/version): main may have moved since.
	Line int    `json:"line,omitempty"`
	Rev  string `json:"rev,omitempty"`
	// A CI item's failed run (its logs go to the session).
	Ref string `json:"ref,omitempty"`
	// A feature made of a fix found too big: the fix's item.
	From  string `json:"from,omitempty"`
	Count int    `json:"count"`
	First int64  `json:"first"`
	Last  int64  `json:"last"`
	// new, working, pr (a PR is open), merged, skipped (not a bug, or not
	// enough to go on), ignored (skipped as harmless and unfixable: never
	// tried again), too_big (a refactor or a design: a real session's
	// job), feature (a fix too big for one, moved to the feature requests),
	// failed (its change never passed), unable (it couldn't do it: the
	// session said so, or its change failed maxAttempts times; told, never
	// picked again unless the user says Retry), dropped (by the user), gone
	// (a failed unit running again, CI green again before a fix).
	Status string `json:"status"`
	Note   string `json:"note,omitempty"` // why it was skipped, failed…
	PR     int    `json:"pr,omitempty"`
	Tried  int64  `json:"tried,omitempty"`
	// Count when last tried: tried again once it has grown since.
	TriedCount int `json:"triedCount,omitempty"`
	// Runs whose change failed in a row: at maxAttempts it is unable.
	Attempts int `json:"attempts,omitempty"`
	// When it was put in the queue: started (Fix now, Build now, an
	// agent's fix_now) while another was being made, it waits its turn,
	// oldest first, and starts once the run before it lets go of the run
	// lock (its PR out, or ended). 0: not queued.
	Queued int64 `json:"queued,omitempty"`
}

// maxAttempts: failed that many times, an item is given up (unable).
const maxAttempts = 2

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
	// A feature request says more (and, made of a fix, what the fixer found).
	room := 600
	if kind == "feature" {
		room = 1500
	}
	in.Items = append(in.Items, Item{
		ID: itemID(key), Key: key, Kind: kind, Text: clip(text, room),
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
	"feature": 1, "regression": 1,
}

func (it Item) feature() bool { return it.Kind == "feature" }

// toFeature moves a fix item to the feature requests (found too big for a
// fix, or by the user's hand): a feature item with its words and what the
// fixer found, the fix item out of the fixes' list.
func (in *Inbox) toFeature(id, why string, now int64) (*Item, error) {
	it := in.find(id)
	if it == nil {
		return nil, errorf("no item %s", id)
	}
	if it.feature() {
		return it, nil
	}
	if it.Status == "pr" {
		return nil, errorf("item %s has a pull request open", id)
	}
	text := it.Text
	if why = strings.TrimSpace(why); why != "" {
		text += "\n\nToo big for a fix: " + why
	}
	from, where := it.ID, it.Where
	it.Status, it.Note, it.Queued = "feature", clip("moved to the feature requests", 300), 0
	f := in.add("feature", "feature:from:"+from, text, where, 1, now)
	f.From = from
	return f, nil
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

// queueable: may wait in the queue, and be started from it.
func (it Item) queueable() bool {
	switch it.Status {
	case "working", "pr", "merged", "dropped", "gone", "ignored", "feature":
		return false
	}
	return true
}

// queue: the queued items, first to start first.
func (in *Inbox) queue() []*Item {
	var q []*Item
	for i := range in.Items {
		if in.Items[i].Queued > 0 {
			q = append(q, &in.Items[i])
		}
	}
	slices.SortStableFunc(q, func(a, b *Item) int { return cmp.Compare(a.Queued, b.Queued) })
	return q
}

// queuePos: its place in the queue, from 1 (0: not queued).
func (in *Inbox) queuePos(id string) int {
	return slices.IndexFunc(in.queue(), func(it *Item) bool { return it.ID == id }) + 1
}

// enqueue puts the item last in the queue (it keeps its place when queued
// already) and says where it is.
func (in *Inbox) enqueue(id string, now int64) (int, error) {
	it := in.find(id)
	if it == nil {
		return 0, errorf("no item %s", id)
	}
	if !it.queueable() {
		return 0, errorf("item %s is %s", id, it.Status)
	}
	if it.Queued == 0 {
		at := now
		if q := in.queue(); len(q) > 0 && q[len(q)-1].Queued >= at {
			at = q[len(q)-1].Queued + 1
		}
		it.Queued = at
	}
	return in.queuePos(id), nil
}

// moveQueued swaps the item with the one before it (by < 0) or after it.
func (in *Inbox) moveQueued(id string, by int) error {
	q := in.queue()
	i := slices.IndexFunc(q, func(it *Item) bool { return it.ID == id })
	if i < 0 {
		return errorf("item %s isn't queued", id)
	}
	j := i + 1
	if by < 0 {
		j = i - 1
	}
	if j >= 0 && j < len(q) {
		q[i].Queued, q[j].Queued = q[j].Queued, q[i].Queued
	}
	return nil
}

// nextQueued: the first queued item that may start now (its kind
// switched on); queued items that can't start any more leave the queue.
func (in *Inbox) nextQueued(cfg Config) *Item {
	for _, it := range in.queue() {
		if !it.queueable() {
			it.Queued = 0
			continue
		}
		if cfg.on(it.feature()) {
			return it
		}
	}
	return nil
}

// pick is the item to work on, among the fixes or the features: the
// user's first, then the most seen.
func (in *Inbox) pick(now int64, feature bool) *Item {
	var best *Item
	score := func(it *Item) int {
		s := it.Count
		if it.Kind == "user" || it.Kind == "regression" {
			s += 1000
		}
		return s
	}
	for i := range in.Items {
		it := &in.Items[i]
		if it.feature() == feature && it.ripe(now) && (best == nil || score(it) > score(best)) {
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
