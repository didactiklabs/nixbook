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
	var found int
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
		for _, w := range ws {
			// A warning printed in a loop counts a few times, not hundreds.
			in.add("qml", "qml:"+w.key(), fmt.Sprintf("The shell prints %q (%s:%d).", w.Msg, w.File, w.Line),
				w.File, min(counts[w.key()], 5), now)
			found++
		}
		for _, c := range toolCrashes(since) {
			in.add("crash", "crash:"+c.tool+":"+c.msg, fmt.Sprintf("The desktop tool %s crashed: %s", c.tool, c.msg),
				"nixbook-shell/scripts/desktop-mcp.py", 1, now)
			found++
		}
		in.LastCollect = now
		return nil
	})
	if err != nil {
		return nil, err
	}
	return map[string]any{"found": found, "items": len(in.Items)}, nil
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
