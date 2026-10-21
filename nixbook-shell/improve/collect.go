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

// collect files what was seen since the last time: the shell's QML
// errors, the desktop tools' crashes, failed units and their logs, the
// last update, CI on main, coredumps, the kernel (sources.go). Plain
// reading and counting, no model; a source it can't read is skipped.
func collect() (map[string]any, error) {
	var prev Inbox
	readJSON(inboxPath(), &prev)
	since := prev.LastCollect
	if since == 0 {
		since = nowMs() - 24*3600*1000
	}
	cfg, _ := loadConfig()
	syncPRs(cfg)
	o := loadOwned()

	// Read first, file after: the inbox stays locked only for the filing.
	var fs []found
	var skipped []string
	if log, err := shellLog(since); err != nil {
		skipped = append(skipped, "the shell's log")
	} else {
		ws, counts := uniqueWarnings(parseWarnings(log))
		for _, w := range ws {
			// A warning printed in a loop counts a few times, not hundreds.
			fs = append(fs, found{
				kind: "qml", key: "qml:" + w.key(), where: w.File, times: min(counts[w.key()], 5),
				text: fmt.Sprintf("The shell prints %q (%s:%d).", w.Msg, w.File, w.Line), ref: itoa(w.Line),
			})
		}
	}
	for _, c := range toolCrashes(since) {
		fs = append(fs, found{
			kind: "crash", key: "crash:" + c.tool + ":" + c.msg, times: 1,
			text: fmt.Sprintf("The desktop tool %s crashed: %s", c.tool, c.msg), where: "nixbook-shell/scripts/desktop-mcp.py",
		})
	}
	failed, stillFailed := failedUnits(o)
	fs = append(fs, failed...)
	fs = append(fs, unitErrors(o, since)...)
	fs = append(fs, deploy(since)...)
	ci, stillRed, ciRead := ciFailures(ghRepo(cfg.Repo), cfg.CIIgnoreJobs)
	fs = append(fs, ci...)
	fs = append(fs, coredumps(o, since)...)
	fs = append(fs, kernelErrors(since)...)

	rev := deployedRev()
	byKind := map[string]int{}
	var fresh, gone int
	in, err := editInbox(func(in *Inbox) error {
		now := nowMs()
		for _, f := range fs {
			it := in.add(f.kind, f.key, f.text, f.where, f.times, now)
			if it.Count == f.times {
				fresh++
			}
			if f.kind == "qml" {
				it.Line, it.Rev = atoi(f.ref), rev
			} else if f.ref != "" {
				it.Ref = f.ref
			}
			byKind[f.kind]++
		}
		// A unit running again, a workflow green again: nothing left to fix.
		for i := range in.Items {
			it := &in.Items[i]
			if it.Status != "new" {
				continue
			}
			if (it.Kind == "service" && !stillFailed[it.Key]) || (it.Kind == "ci" && ciRead && !stillRed[it.Key]) {
				it.Status, it.Note = "gone", "fixed meanwhile"
				gone++
			}
		}
		in.LastCollect = now
		return nil
	})
	if err != nil {
		logEvent("error", "Looking for bugs: "+err.Error())
		return nil, err
	}
	what := "nothing new"
	if len(fs) > 0 {
		var parts []string
		for _, k := range []string{"qml", "crash", "service", "log", "deploy", "warning", "ci", "coredump", "info"} {
			if byKind[k] > 0 {
				parts = append(parts, fmt.Sprintf("%d %s", byKind[k], kindText[k]))
			}
		}
		what = fmt.Sprintf("%d new, %d seen again (%s)", fresh, len(fs)-fresh, strings.Join(parts, ", "))
	}
	if gone > 0 {
		what += fmt.Sprintf("; %d gone by themselves", gone)
	}
	if len(skipped) > 0 {
		what += "; couldn't read " + strings.Join(skipped, ", ")
	}
	logEvent("look", "Looked for bugs: "+what)
	return map[string]any{"found": len(fs), "new": fresh, "gone": gone, "items": len(in.Items)}, nil
}

// In words, for the activity.
var kindText = map[string]string{
	"qml": "shell errors", "crash": "tool crashes", "service": "failed units", "log": "unit errors",
	"deploy": "failed updates", "warning": "Nix warnings", "ci": "CI failures", "coredump": "crashes",
	"info": "not nixbook's",
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
