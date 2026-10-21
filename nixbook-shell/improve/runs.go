package main

import (
	"fmt"
	"path/filepath"
	"time"
)

// A Run is one try at an inbox item, from the fixing session to the merge
// and the deployed shell's check. runs.json keeps the last ones for
// Settings and the health check.
type Run struct {
	ID       string `json:"id"`
	Item     string `json:"item"`
	ItemText string `json:"itemText"`
	Manual   bool   `json:"manual,omitempty"` // "Fix now": not counted in the day's runs
	Started  int64  `json:"started"`
	Finished int64  `json:"finished,omitempty"`
	// clone, fix, check, push, ci, ready, merged, health; done once over.
	Stage string `json:"stage"`
	// What it does right now, live: "Claude reads …", a check running.
	Doing string `json:"doing,omitempty"`
	// "" (going on), pr (open, waiting for the user), merged, skipped,
	// too_big, failed, dropped, reverted.
	Outcome   string   `json:"outcome"`
	Note      string   `json:"note,omitempty"`
	Type      string   `json:"type,omitempty"` // fix, polish
	Title     string   `json:"title,omitempty"`
	Branch    string   `json:"branch,omitempty"`
	PR        int      `json:"pr,omitempty"`
	URL       string   `json:"url,omitempty"`
	Files     []Change `json:"files,omitempty"`
	Sensitive bool     `json:"sensitive,omitempty"`
	AutoMerge bool     `json:"autoMerge,omitempty"`
	CI        string   `json:"ci,omitempty"` // pending, pass, fail
	CIRetried bool     `json:"ciRetried,omitempty"`
	Merged    string   `json:"merged,omitempty"` // its commit on main
	MainCI    string   `json:"mainCi,omitempty"`
	// The headless shell's warnings in its files before the change: what
	// the deployed shell is compared with.
	Before  []Warning `json:"before,omitempty"`
	Checked bool      `json:"checked,omitempty"` // the deployed shell was checked
	Cost    float64   `json:"cost,omitempty"`
	Session string    `json:"session,omitempty"`
	// The process making it, until its PR is out: what Stop ends.
	PID int `json:"pid,omitempty"`
}

const runsMax = 40

func runsPath() string { return filepath.Join(stateDir(), "runs.json") }

func readRuns() ([]Run, error) {
	var rs []Run
	return rs, readJSON(runsPath(), &rs)
}

// editRun changes one run (added when new) under the runs' lock.
func editRun(id string, fn func(*Run)) (Run, error) {
	unlock, err := lock("runs.lock", true)
	if err != nil {
		return Run{}, err
	}
	defer unlock()
	rs, err := readRuns()
	if err != nil {
		return Run{}, err
	}
	i := len(rs)
	for j := range rs {
		if rs[j].ID == id {
			i = j
		}
	}
	if i == len(rs) {
		rs = append(rs, Run{ID: id, Started: nowMs()})
	}
	fn(&rs[i])
	r := rs[i]
	if len(rs) > runsMax {
		rs = rs[len(rs)-runsMax:]
	}
	return r, writeJSON(runsPath(), rs)
}

func findRun(pr int, id string) (Run, error) {
	rs, err := readRuns()
	if err != nil {
		return Run{}, err
	}
	for i := len(rs) - 1; i >= 0; i-- {
		if (pr != 0 && rs[i].PR == pr) || (id != "" && rs[i].ID == id) {
			return rs[i], nil
		}
	}
	if pr != 0 {
		return Run{}, errorf("no fix with PR #%d", pr)
	}
	return Run{}, errorf("no run %s", id)
}

// runsToday: the runs started on its own today ("Fix now" isn't counted).
func runsToday(rs []Run) int {
	y, m, d := time.Now().Date()
	start := time.Date(y, m, d, 0, 0, 0, 0, time.Local).UnixMilli()
	n := 0
	for _, r := range rs {
		if !r.Manual && r.Started >= start {
			n++
		}
	}
	return n
}

func newRunID() string { return fmt.Sprintf("%x", time.Now().UnixNano())[:12] }
