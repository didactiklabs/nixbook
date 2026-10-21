package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

// The other things to fix, beyond the shell's QML errors and the desktop
// tools' crashes, read with what the user can already read (no new
// permission: what can't be read is skipped):
//   - service: a failed systemd unit nixbook defines (system or user);
//   - log: an error line in the log of a unit nixbook defines;
//   - deploy: the last system update failed; warning: a Nix warning in it;
//   - ci: a workflow failing on main (with the token);
//   - coredump: a program nixbook packages crashed;
//   - info: the same about what isn't nixbook's (another app's crash, the
//     kernel, a unit it doesn't define): listed, never ripe, sent to a
//     session only by Fix now.
// What nixbook defines comes from Nix: owned.json (its user units and
// packages, homeManagerModules/nixbookShellConfig.nix) and
// /etc/nixbook/owned-units.json (its system units, nixosModules/ownedUnits.nix).

type owned struct {
	system, user map[string]bool
	packages     []string
}

func loadOwned() owned {
	o := owned{system: map[string]bool{}, user: map[string]bool{}}
	userFile := os.Getenv("NIXBOOK_IMPROVE_OWNED")
	if userFile == "" {
		userFile = filepath.Join(xdg("XDG_CONFIG_HOME", ".config"), "nixbook-shell", "owned.json")
	}
	systemFile := os.Getenv("NIXBOOK_IMPROVE_OWNED_SYSTEM")
	if systemFile == "" {
		systemFile = "/etc/nixbook/owned-units.json"
	}
	var u struct {
		UserServices, UserTimers, Packages []string
	}
	readJSON(userFile, &u)
	var s struct{ Services, Timers []string }
	readJSON(systemFile, &s)
	for _, n := range append(u.UserServices, u.UserTimers...) {
		o.user[n] = true
	}
	for _, n := range append(s.Services, s.Timers...) {
		o.system[n] = true
	}
	o.packages = u.Packages
	return o
}

// unitName: "foo.service" -> "foo", "foo@bar.service" -> "foo@".
func unitName(unit string) string {
	n := strings.TrimSuffix(strings.TrimSuffix(unit, ".service"), ".timer")
	if i := strings.Index(n, "@"); i >= 0 {
		n = n[:i+1]
	}
	return n
}

func (o owned) unit(scope, unit string) bool {
	n := unitName(unit)
	if scope == "user" {
		return o.user[n]
	}
	// Deploying is nixbook's, whatever module defines the unit.
	return o.system[n] || strings.HasPrefix(n, "home-manager-") || strings.HasPrefix(n, "nixos-upgrade")
}

// found: something a source saw, for the inbox.
type found struct {
	kind, key, text, where, ref string
	times                       int
}

func scopeArgs(scope string, args ...string) []string {
	if scope == "user" {
		return append([]string{"--user"}, args...)
	}
	return args
}

// unitLog: a unit's last log lines (empty when its journal can't be read).
func unitLog(scope, unit string, n int) string {
	out, _ := cmd("", 20*time.Second, "", "journalctl", scopeArgs(scope, "-u", unit, "-n", itoa(n), "-o", "cat", "--no-pager")...)
	var lines []string
	for _, l := range strings.Split(strings.TrimSpace(out), "\n") {
		if l = strings.TrimSpace(l); l != "" && !strings.HasPrefix(l, "-- ") {
			lines = append(lines, clip(l, 300))
		}
	}
	return strings.Join(lines, "\n")
}

// failedUnits: the failed units, and which keys are still failing (an
// item whose unit came back is done).
func failedUnits(o owned) (fs []found, still map[string]bool) {
	still = map[string]bool{}
	for _, scope := range []string{"system", "user"} {
		out, err := cmd("", 20*time.Second, "", "systemctl", scopeArgs(scope, "--failed", "--plain", "--no-legend", "--no-pager")...)
		if err != nil {
			continue
		}
		for _, line := range strings.Split(out, "\n") {
			f := strings.Fields(line)
			if len(f) == 0 || !strings.Contains(f[0], ".") {
				continue
			}
			unit := f[0]
			if o.unit(scope, unit) {
				key := "service:" + scope + ":" + unit
				still[key] = true
				fs = append(fs, found{
					kind: "service", key: key, where: unit, times: 1,
					text: fmt.Sprintf("The %s unit %s, which nixbook defines, has failed. Its last log lines:\n%s",
						scope, unit, unitLog(scope, unit, 20)),
				})
			} else {
				fs = append(fs, found{
					kind: "info", key: "info:service:" + scope + ":" + unit, where: unit, times: 1,
					text: fmt.Sprintf("The %s unit %s failed (not one nixbook defines).", scope, unit),
				})
			}
		}
	}
	return fs, still
}

// unitErrors: error lines in the logs of the units nixbook defines (the
// shell's own are the QML source's).
func unitErrors(o owned, sinceMs int64) []found {
	var fs []found
	counts := map[string]int{}
	for _, scope := range []string{"system", "user"} {
		out, _ := cmd("", time.Minute, "", "journalctl", scopeArgs(scope, "-p", "err", "--since", fmt.Sprintf("@%d", sinceMs/1000),
			"-o", "json", "--no-pager", "-n", "3000")...)
		field := "_SYSTEMD_UNIT"
		if scope == "user" {
			field = "_SYSTEMD_USER_UNIT"
		}
		for _, line := range strings.Split(out, "\n") {
			var e map[string]json.RawMessage
			if json.Unmarshal([]byte(line), &e) != nil {
				continue
			}
			var unit, msg string
			json.Unmarshal(e[field], &unit)
			if json.Unmarshal(e["MESSAGE"], &msg) != nil || unit == "" || msg == "" {
				continue // a binary message, or not a unit's
			}
			if unit == "nixbook-shell.service" || !o.unit(scope, unit) {
				continue
			}
			key := "log:" + scope + ":" + unit + ":" + normalizeMsg(msg)
			if counts[key] == 0 {
				fs = append(fs, found{
					kind: "log", key: key, where: unit,
					text: fmt.Sprintf("The %s unit %s, which nixbook defines, logged this error: %s", scope, unit, clip(msg, 400)),
				})
			}
			counts[key]++
		}
	}
	for i := range fs {
		// An error logged in a loop counts a few times, not hundreds.
		fs[i].times = min(counts[fs[i].key], 5)
	}
	return fs
}

var nixWarningRe = regexp.MustCompile(`(evaluation warning:|trace: warning:)\s*(.+)$`)

// deploy: the last system update (osupdate, /run/nixos-upgrade/status.json)
// failed, or printed Nix warnings, since then.
func deploy(sinceMs int64) []found {
	path := os.Getenv("NIXBOOK_IMPROVE_UPGRADE")
	if path == "" {
		path = "/run/nixos-upgrade/status.json"
	}
	var st struct {
		State    string `json:"state"`
		Finished int64  `json:"finished"`
		Tail     string `json:"tail"`
	}
	if readJSON(path, &st) != nil || st.Finished*1000 <= sinceMs {
		return nil
	}
	lines := strings.Split(strings.TrimSpace(st.Tail), "\n")
	var fs []found
	if st.State == "failed" {
		errLine := lines[len(lines)-1]
		for i := len(lines) - 1; i >= 0; i-- {
			if strings.Contains(lines[i], "error:") {
				errLine = lines[i]
				break
			}
		}
		fs = append(fs, found{
			kind: "deploy", key: "deploy:" + normalizeMsg(errLine), times: 1,
			text: "The last system update (osupdate) failed. The end of its log:\n" +
				strings.Join(lines[max(0, len(lines)-30):], "\n"),
		})
	}
	seen := map[string]bool{}
	for _, l := range lines {
		if m := nixWarningRe.FindStringSubmatch(l); m != nil && !seen[m[2]] {
			seen[m[2]] = true
			fs = append(fs, found{
				kind: "warning", key: "warning:" + normalizeMsg(m[2]), times: 1,
				text: "The system update printed this Nix warning: " + clip(m[2], 400),
			})
		}
	}
	return fs
}

// ciFailures: workflows whose latest run on main failed (with the token),
// and which keys still fail.
func ciFailures(repo string) (fs []found, still map[string]bool, ok bool) {
	still = map[string]bool{}
	if repo == "" || token() == "" {
		return nil, still, false
	}
	var runs []struct {
		DatabaseID   int64  `json:"databaseId"`
		Status       string `json:"status"`
		Conclusion   string `json:"conclusion"`
		WorkflowName string `json:"workflowName"`
		HeadSha      string `json:"headSha"`
		DisplayTitle string `json:"displayTitle"`
		URL          string `json:"url"`
	}
	if ghJSON(&runs, "run", "list", "--repo", repo, "--branch", "main", "--limit", "30",
		"--json", "databaseId,status,conclusion,workflowName,headSha,displayTitle,url") != nil {
		return nil, still, false
	}
	done := map[string]bool{}
	for _, r := range runs { // newest first
		if r.Status != "completed" || done[r.WorkflowName] || r.Conclusion == "cancelled" || r.Conclusion == "skipped" {
			continue
		}
		done[r.WorkflowName] = true
		if r.Conclusion != "failure" {
			continue
		}
		key := "ci:" + r.WorkflowName
		still[key] = true
		fs = append(fs, found{
			kind: "ci", key: key, where: r.URL, ref: fmt.Sprint(r.DatabaseID), times: 1,
			text: fmt.Sprintf("CI's %q workflow fails on main (%s: %s).", r.WorkflowName, r.HeadSha[:min(7, len(r.HeadSha))], clip(r.DisplayTitle, 120)),
		})
	}
	return fs, still, true
}

// coredumps: programs that crashed since then (the user's own, which
// coredumpctl lists without privileges): nixbook's packages' to fix, the
// rest to know.
func coredumps(o owned, sinceMs int64) []found {
	out, err := cmd("", 30*time.Second, "", "coredumpctl", "list", "--since", fmt.Sprintf("@%d", sinceMs/1000),
		"--json=short", "--no-pager")
	if err != nil {
		return nil // none, or no coredumps here
	}
	var dumps []struct {
		Exe string `json:"exe"`
		Sig int    `json:"sig"`
	}
	if json.Unmarshal([]byte(out), &dumps) != nil {
		return nil
	}
	var fs []found
	counts := map[string]int{}
	for _, d := range dumps {
		base := filepath.Base(d.Exe)
		pkg := storeName(d.Exe)
		ours := strings.HasPrefix(base, "nixbook-")
		for _, p := range o.packages {
			ours = ours || strings.HasPrefix(pkg, p+"-") || pkg == p
		}
		kind, key, text := "info", fmt.Sprintf("info:core:%s:%d", base, d.Sig),
			fmt.Sprintf("%s crashed (signal %d; not a program nixbook packages).", base, d.Sig)
		if ours {
			kind, key, text = "coredump", fmt.Sprintf("core:%s:%d", base, d.Sig),
				fmt.Sprintf("%s (%s, packaged by nixbook) crashed with signal %d.", base, pkg, d.Sig)
		}
		if counts[key] == 0 {
			fs = append(fs, found{kind: kind, key: key, text: text, where: d.Exe})
		}
		counts[key]++
	}
	for i := range fs {
		fs[i].times = min(counts[fs[i].key], 5)
	}
	return fs
}

// storeName: "name-version" of a /nix/store path, "" otherwise.
func storeName(path string) string {
	rest, ok := strings.CutPrefix(path, "/nix/store/")
	if !ok {
		return ""
	}
	seg, _, _ := strings.Cut(rest, "/")
	if _, name, ok := strings.Cut(seg, "-"); ok {
		return name
	}
	return ""
}

// kernelErrors: the kernel's error lines (from the journal, which the
// user's group may read; dmesg itself is restricted): to know only.
func kernelErrors(sinceMs int64) []found {
	out, _ := cmd("", 30*time.Second, "", "journalctl", "-k", "-p", "err", "--since", fmt.Sprintf("@%d", sinceMs/1000),
		"-o", "cat", "--no-pager", "-n", "300")
	var fs []found
	counts := map[string]int{}
	for _, l := range strings.Split(out, "\n") {
		if l = strings.TrimSpace(l); l == "" || strings.HasPrefix(l, "-- ") {
			continue
		}
		key := "info:kernel:" + normalizeMsg(l)
		if counts[key] == 0 {
			fs = append(fs, found{kind: "info", key: key, text: "Kernel: " + clip(l, 300)})
		}
		counts[key]++
	}
	for i := range fs {
		fs[i].times = min(counts[fs[i].key], 5)
	}
	return fs
}
