package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// collect files what the shell's log and the desktop tools' audit log
// showed since the last time: plain reading and counting, no model.
func collect() (map[string]any, error) {
	var found, fresh int
	in, err := editInbox(func(in *Inbox) error {
		since := in.LastCollect
		if since == 0 {
			since = nowMs() - 24*3600*1000
		}
		now := nowMs()
		log, err := shellLog(since)
		if err != nil {
			return err
		}
		ws, counts := uniqueWarnings(parseWarnings(log))
		rev := deployedRev()
		for _, w := range ws {
			// A warning printed in a loop counts a few times, not hundreds.
			n := min(counts[w.key()], 5)
			it := in.add("qml", "qml:"+w.key(), fmt.Sprintf("The shell prints %q (%s:%d).", w.Msg, w.File, w.Line),
				w.File, n, now)
			if it.Count == n {
				fresh++
			}
			it.Line, it.Rev = w.Line, rev
			found++
		}
		for _, c := range toolCrashes(since) {
			if in.add("crash", "crash:"+c.tool+":"+c.msg, fmt.Sprintf("The desktop tool %s crashed: %s", c.tool, c.msg),
				"nixbook-shell/scripts/desktop-mcp.py", 1, now).Count == 1 {
				fresh++
			}
			found++
		}
		in.LastCollect = now
		return nil
	})
	if err != nil {
		logEvent("error", "Looking for bugs: "+err.Error())
		return nil, err
	}
	switch {
	case found == 0:
		logEvent("look", "Looked for bugs in the shell's log and the tools' crashes: nothing new")
	default:
		logEvent("look", fmt.Sprintf("Looked for bugs: %d new, %d seen again", fresh, found-fresh))
	}
	return map[string]any{"found": found, "new": fresh, "items": len(in.Items)}, nil
}

// shellLog: the nixbook-shell unit's journal since then (NIXBOOK_IMPROVE_LOG,
// a file, in tests).
func shellLog(sinceMs int64) (string, error) {
	if f := os.Getenv("NIXBOOK_IMPROVE_LOG"); f != "" {
		b, err := os.ReadFile(f)
		return string(b), err
	}
	out, err := exec.Command("journalctl", "--user", "-u", "nixbook-shell.service", "-o", "cat", "--no-pager",
		"-n", "50000", "--since", fmt.Sprintf("@%d", sinceMs/1000)).Output()
	if err != nil {
		return "", errorf("the shell's journal: %v", err)
	}
	return string(out), nil
}

type crash struct{ tool, msg string }

// toolCrashes: the desktop tools that raised (a bug, not a refusal) since
// then, from nixbook-desktop-mcp's audit log.
func toolCrashes(sinceMs int64) []crash {
	path := filepath.Join(xdg("XDG_STATE_HOME", ".local/state"), "nixbook-shell", "desktop-mcp.log")
	var out []crash
	for _, p := range []string{path + ".1", path} {
		f, err := os.Open(p)
		if err != nil {
			continue
		}
		sc := bufio.NewScanner(f)
		sc.Buffer(make([]byte, 64*1024), 1<<20)
		for sc.Scan() {
			var e struct{ Time, Tool, Outcome string }
			if json.Unmarshal(sc.Bytes(), &e) != nil || !strings.HasPrefix(e.Outcome, "crash:") {
				continue
			}
			t, err := time.Parse("2006-01-02T15:04:05-0700", e.Time)
			if err != nil || t.UnixMilli() <= sinceMs {
				continue
			}
			out = append(out, crash{e.Tool, normalizeMsg(strings.TrimSpace(strings.TrimPrefix(e.Outcome, "crash:")))})
		}
		f.Close()
	}
	return out
}

// deployedRev: the revision this computer runs (/etc/nixos/version, as the
// update check reads it; NIXBOOK_VERSION_FILE in tests), "" if unknown or
// built from uncommitted changes.
func deployedRev() string {
	path := os.Getenv("NIXBOOK_VERSION_FILE")
	if path == "" {
		path = "/etc/nixos/version"
	}
	var v struct {
		Rev   string `json:"rev"`
		Dirty bool   `json:"dirty"`
	}
	if readJSON(path, &v) != nil || v.Dirty || strings.Trim(v.Rev, "0") == "" {
		return ""
	}
	return v.Rev
}
