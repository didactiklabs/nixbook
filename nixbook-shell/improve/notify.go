package main

import (
	"os/exec"
	"strings"
	"time"
)

// notify shows a notification ("Desktop agents") and, with actions
// ("merge=Merge"…), waits for the one the user picks ("" when dismissed).
func notify(summary, body string, urgency string, actions ...string) string {
	if _, err := exec.LookPath("notify-send"); err != nil {
		return ""
	}
	args := []string{"--app-name=Desktop agents", "--icon=system-software-update", "--urgency=" + urgency}
	limit := 30 * time.Second
	if len(actions) > 0 {
		args = append(args, "--wait")
		for _, a := range actions {
			args = append(args, "--action="+a)
		}
		// Left unanswered, it stays in the history: Settings has the
		// same buttons.
		limit = 12 * time.Hour
	}
	out, _ := cmd("", limit, "", "notify-send", append(args, summary, body)...)
	return strings.TrimSpace(out)
}
