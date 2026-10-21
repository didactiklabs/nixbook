package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"
)

// health looks at the shell running a deployed fix (rev: the deployed
// revision, /etc/nixos/version): a QML warning in the fix's files the shell
// didn't print before, or the shell restarting, and the user is offered the
// revert. Plain reading, no model.
func health(rev string) (map[string]any, error) {
	cfg, err := loadConfig()
	if err != nil {
		return nil, err
	}
	rs, err := readRuns()
	if err != nil {
		return nil, err
	}
	var due []Run
	for _, r := range rs {
		if r.Outcome == "merged" && !r.Checked && r.Merged != "" {
			due = append(due, r)
		}
	}
	if len(due) == 0 || rev == "" || strings.Trim(rev, "0") == "" {
		return map[string]any{"checked": 0}, nil
	}
	repo := repoDir()
	fetchGit(repo, "fetch", "origin", "main")
	log, restarts := runningShell()
	var known Inbox
	readJSON(inboxPath(), &known)
	checked := 0
	for _, r := range due {
		if _, err := git(repo, "merge-base", "--is-ancestor", r.Merged, rev); err != nil {
			continue // not deployed yet
		}
		checked++
		editRun(r.ID, func(x *Run) { x.Checked = true })
		if why := suspect(r, parseWarnings(log), restarts, known); why != "" {
			if _, err := revert(cfg, r, why); err != nil {
				return nil, err
			}
		}
	}
	return map[string]any{"checked": checked}, nil
}

// suspect: why the deployed fix looks broken ("" when it doesn't): a
// warning in its files that neither the headless shell before it nor the
// inbox (the running shell, before it) had, or the shell restarting.
func suspect(r Run, ws []Warning, restarts int, known Inbox) string {
	files := map[string]bool{}
	for _, c := range r.Files {
		files[c.Path] = true
	}
	var mine []Warning
	for _, w := range ws {
		if files[w.File] {
			mine = append(mine, w)
		}
	}
	for _, w := range newWarnings(r.Before, mine) {
		if it := (&known).findKey("qml:" + w.key()); it != nil && it.First < r.Started {
			continue
		}
		return fmt.Sprintf("the shell prints %q (%s:%d) since it", w.Msg, w.File, w.Line)
	}
	if restarts > 0 && touches(r.Files, "nixbook-shell/") {
		return fmt.Sprintf("the shell restarted %d times since it", restarts)
	}
	return ""
}

func (in *Inbox) findKey(key string) *Item {
	for i := range in.Items {
		if in.Items[i].Key == key {
			return &in.Items[i]
		}
	}
	return nil
}

// runningShell: the running shell's output (this start of its unit) and
// how often systemd restarted it. NIXBOOK_IMPROVE_LOG in tests.
func runningShell() (string, int) {
	if f := os.Getenv("NIXBOOK_IMPROVE_LOG"); f != "" {
		b, _ := os.ReadFile(f)
		return string(b), atoi(os.Getenv("NIXBOOK_IMPROVE_RESTARTS"))
	}
	show := func(p string) string {
		out, _ := exec.Command("systemctl", "--user", "show", "-p", p, "--value", "nixbook-shell.service").Output()
		return strings.TrimSpace(string(out))
	}
	inv := show("InvocationID")
	if inv == "" {
		return "", 0
	}
	out, _ := cmd("", time.Minute, "", "journalctl", "--user", "_SYSTEMD_INVOCATION_ID="+inv, "-o", "cat", "--no-pager", "-n", "50000")
	return out, atoi(show("NRestarts"))
}
