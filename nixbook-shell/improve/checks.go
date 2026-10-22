package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// diff stages everything the session changed and lists it.
func diff(repo string) ([]Change, error) {
	if _, err := git(repo, "add", "-A"); err != nil {
		return nil, err
	}
	num, err := git(repo, "diff", "--cached", "--numstat", "--no-renames")
	if err != nil {
		return nil, err
	}
	names, err := git(repo, "diff", "--cached", "--name-status", "--no-renames")
	if err != nil {
		return nil, err
	}
	return parseDiff(num, names), nil
}

func parseDiff(numstat, nameStatus string) []Change {
	status := map[string]string{}
	for _, l := range strings.Split(nameStatus, "\n") {
		if s, p, ok := strings.Cut(l, "\t"); ok {
			status[p] = s[:1]
		}
	}
	var out []Change
	for _, l := range strings.Split(numstat, "\n") {
		f := strings.SplitN(l, "\t", 3)
		if len(f) != 3 {
			continue
		}
		c := Change{Path: f[2], Status: status[f[2]], Binary: f[0] == "-"}
		c.Added, c.Deleted = atoi(f[0]), atoi(f[1])
		out = append(out, c)
	}
	return out
}

// failLines: the test suites' "FAIL - …" lines and their indented details.
func failLines(out string) string {
	var b strings.Builder
	in := false
	for _, l := range strings.Split(out, "\n") {
		switch {
		case strings.HasPrefix(l, "FAIL"):
			in = true
		case !in || !strings.HasPrefix(l, " "):
			in = false
			continue
		}
		if b.Len()+len(l) > 1500 {
			break
		}
		b.WriteString(l + "\n")
	}
	return strings.TrimSpace(b.String())
}

type checkResult struct {
	ok       bool
	report   []string // for the PR: what ran and how it went
	feedback string   // for the session's second try
	before   []Warning
}

func touches(changes []Change, prefixes ...string) bool {
	for _, c := range changes {
		for _, p := range prefixes {
			if strings.HasPrefix(c.Path, p) || (strings.HasPrefix(p, "*") && strings.HasSuffix(c.Path, p[1:])) {
				return true
			}
		}
	}
	return false
}

// check builds and tests the change in repo (based on base): formatting,
// the tests of what it touched, and the shell loaded headless, compared
// with the base's.
func check(repo, base string, changes []Change, runDir string) checkResult {
	res := checkResult{ok: true}
	fail := func(what, out string) {
		res.ok = false
		res.report = append(res.report, "- ❌ "+what)
		// Its failures first: the note (cut short) shows them, not a run of "ok".
		if f := failLines(out); f != "" {
			out = f + "\n\nThe end of its output:\n" + tail(out, 3000)
		} else {
			out = tail(out, 4000)
		}
		res.feedback += fmt.Sprintf("%s failed:\n%s\n\n", what, out)
	}
	pass := func(what string) { res.report = append(res.report, "- ✅ "+what) }

	devenv, _ := exec.LookPath("devenv")
	inDevenv := func(limit time.Duration, args ...string) (string, error) {
		if devenv == "" {
			return cmd(repo, limit, "", args[0], args[1:]...)
		}
		return cmd(repo, limit, "", devenv, append([]string{"shell", "--"}, args...)...)
	}

	var files []string
	for _, c := range changes {
		files = append(files, c.Path)
	}
	// treefmt formats what it knows (not the QML); its changes are kept.
	if devenv != "" {
		doing("Formatting (treefmt)")
		if _, err := inDevenv(20*time.Minute, append([]string{"treefmt", "--no-cache"}, files...)...); err != nil {
			// Not the change's fault: CI's lint job has the last word.
			res.report = append(res.report, "- ⚠️ treefmt didn't run: "+clip(err.Error(), 200))
		} else {
			pass("formatted (treefmt)")
			git(repo, "add", "-A")
		}
	}

	if touches(changes, "nixbook-shell/scripts/", "nixbook-shell/accounts/", "nixbook-shell/keep") {
		doing("Running tests/run.sh shell")
		if out, err := inDevenv(40*time.Minute, "bash", "tests/run.sh", "shell"); err != nil {
			fail("tests/run.sh shell", out+err.Error())
		} else {
			pass("tests/run.sh shell")
		}
	}
	if touches(changes, "*.nix") {
		doing("Running tests/run.sh repo")
		if out, err := inDevenv(40*time.Minute, "bash", "tests/run.sh", "repo"); err != nil {
			fail("tests/run.sh repo", out+err.Error())
		} else {
			pass("tests/run.sh repo")
		}
	}

	if touches(changes, "nixbook-shell/") {
		doing("Starting the shell headless, as it was (once per revision)")
		baseOK, before, err := baseline(repo, base)
		res.before = before
		switch {
		case err != nil:
			res.report = append(res.report, "- ⚠️ the headless shell's baseline didn't run: "+clip(err.Error(), 200))
		default:
			out := filepath.Join(runDir, "shell")
			os.RemoveAll(out)
			doing("Starting the shell headless, with the change")
			_, lerr := cmd(repo, 15*time.Minute, "", "bash", filepath.Join(repo, "nixbook-shell/tests/shell-loads.sh"),
				filepath.Join(repo, "nixbook-shell"), out)
			log, _ := os.ReadFile(filepath.Join(out, "log.txt"))
			after := parseWarnings(string(log))
			added := newWarnings(before, after)
			switch {
			case lerr != nil && baseOK:
				build, _ := os.ReadFile(filepath.Join(out, "build.txt"))
				fail("the shell, started headless", lerr.Error()+"\n"+tail(string(build), 2500)+"\n"+tail(string(log), 2500))
			case len(added) > 0:
				var b strings.Builder
				for _, w := range added {
					fmt.Fprintf(&b, "%s:%d: %s\n", w.File, w.Line, w.Msg)
				}
				fail(fmt.Sprintf("the shell, started headless (%d new QML warnings)", len(added)), b.String())
			default:
				fixed := len(newWarnings(after, before))
				pass(fmt.Sprintf("the shell starts headless with no new QML warnings (%d fewer than before)", fixed))
			}
		}
	}
	return res
}

// baseline: the base's shell, started headless once per revision.
func baseline(repo, rev string) (bool, []Warning, error) {
	cache := filepath.Join(dataDir(), "baseline", rev+".json")
	var b struct {
		OK       bool      `json:"ok"`
		Warnings []Warning `json:"warnings"`
	}
	if err := readJSON(cache, &b); err == nil && b.Warnings != nil {
		return b.OK, b.Warnings, nil
	}
	wt := filepath.Join(dataDir(), "base")
	git(repo, "worktree", "remove", "--force", wt)
	os.RemoveAll(wt)
	if _, err := git(repo, "worktree", "add", "--force", "--detach", wt, rev); err != nil {
		return false, nil, err
	}
	defer git(repo, "worktree", "remove", "--force", wt)
	out := filepath.Join(dataDir(), "baseline", rev)
	_, lerr := cmd(wt, 15*time.Minute, "", "bash", filepath.Join(wt, "nixbook-shell/tests/shell-loads.sh"),
		filepath.Join(wt, "nixbook-shell"), out)
	log, err := os.ReadFile(filepath.Join(out, "log.txt"))
	if err != nil {
		return false, nil, errorf("the base's shell: %v", lerr)
	}
	b.OK, b.Warnings = lerr == nil, parseWarnings(string(log))
	if b.Warnings == nil {
		b.Warnings = []Warning{}
	}
	// One revision kept: the next run's base is newer.
	os.RemoveAll(filepath.Join(dataDir(), "baseline"))
	return b.OK, b.Warnings, writeJSON(cache, b)
}
