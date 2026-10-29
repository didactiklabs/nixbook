package main

import (
	"path/filepath"
	"strings"
)

// What it did and decided, newest last (activity.json, Settings'
// Activity): a look for bugs, why no fix was started, a fix's start,
// retries and end, CI, merges, errors. Without it, idle and broken look
// the same from the outside.
type Event struct {
	Time int64  `json:"time"`
	Kind string `json:"kind"` // look, wait, start, retry, done, pr, ci, merged, broke, error
	Text string `json:"text"`
	// About a feature (Settings shows it with the features).
	Feature bool `json:"feature,omitempty"`
}

// forFeature: the events logged now are a feature's (set once the run, or
// the PR answered, is known).
var forFeature bool

const activityMax = 40

func activityPath() string { return filepath.Join(stateDir(), "activity.json") }

func logEvent(kind, text string) {
	unlock, err := lock("activity.lock", true)
	if err != nil {
		return
	}
	defer unlock()
	var evs []Event
	readJSON(activityPath(), &evs)
	evs = append(evs, Event{Time: nowMs(), Kind: kind, Text: clip(text, 400), Feature: forFeature})
	if len(evs) > activityMax {
		evs = evs[len(evs)-activityMax:]
	}
	writeJSON(activityPath(), evs)
}

// doing tells the run going on what it does right now (Settings shows it
// live): the session's file reads and edits, each check.
var doing = func(string) {}

func doingFor(id string) func(string) {
	return func(s string) { editRun(id, func(r *Run) { r.Doing = clip(s, 200) }) }
}

// describeTool: a tool call of the session, in words.
func describeTool(name string, input map[string]any, dir string) string {
	str := func(k string) string {
		s, _ := input[k].(string)
		return strings.TrimPrefix(strings.TrimPrefix(s, dir), "/")
	}
	switch name {
	case "Read":
		return "V reads " + str("file_path")
	case "Edit", "Write", "MultiEdit":
		return "V edits " + str("file_path")
	case "Grep":
		return "V searches for “" + clip(str("pattern"), 60) + "”"
	case "Glob":
		return "V looks for " + clip(str("pattern"), 60)
	case "StructuredOutput":
		return "V writes its answer"
	}
	return "V: " + name
}

// waitingSummary: why nothing is ripe, for the activity.
func waitingSummary(in Inbox) string {
	var parts []string
	for _, it := range in.Items {
		if it.Status != "new" || it.feature() {
			continue
		}
		need := ripeCount[it.Kind]
		if it.Count < need {
			parts = append(parts, clip(it.Text, 50)+" ("+itoa(it.Count)+"/"+itoa(need)+")")
		}
	}
	if len(parts) == 0 {
		return "nothing to fix or build in the inbox"
	}
	return "nothing seen often enough yet: " + strings.Join(parts[:min(len(parts), 3)], "; ")
}
