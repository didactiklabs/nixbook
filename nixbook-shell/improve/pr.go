package main

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"time"
)

// After the PR: its checks, then the user's answer (or the merge on its
// own), then main's checks and the deployed shell.

type ciCheck struct {
	Bucket string `json:"bucket"` // pass, fail, pending, skipping, cancel
	Name   string `json:"name"`
	Link   string `json:"link"`
}

// ciState: pass, fail or pending, and the failed checks.
func ciState(repo string, pr int) (string, []ciCheck) {
	var cs []ciCheck
	// gh exits non-zero while checks fail or wait: the JSON is still there.
	out, _ := cmd("", 2*time.Minute, "", "gh", "pr", "checks", fmt.Sprint(pr), "--repo", repo, "--json", "bucket,name,link")
	if json.Unmarshal([]byte(out), &cs) != nil || len(cs) == 0 {
		return "pending", nil
	}
	state := "pass"
	var failed []ciCheck
	for _, c := range cs {
		switch c.Bucket {
		case "fail", "cancel":
			failed = append(failed, c)
		case "pending":
			if state == "pass" {
				state = "pending"
			}
		}
	}
	if len(failed) > 0 && state != "pending" {
		return "fail", failed
	}
	return state, failed
}

var runIDRe = regexp.MustCompile(`/actions/runs/(\d+)`)

// failedLogs: the end of the failed jobs' logs, for the session's retry.
func failedLogs(repo string, failed []ciCheck) string {
	var b strings.Builder
	seen := map[string]bool{}
	for _, c := range failed {
		m := runIDRe.FindStringSubmatch(c.Link)
		if m == nil || seen[m[1]] {
			continue
		}
		seen[m[1]] = true
		out, _ := cmd("", 3*time.Minute, "", "gh", "run", "view", m[1], "--repo", repo, "--log-failed")
		fmt.Fprintf(&b, "== %s ==\n%s\n", c.Name, tail(out, 5000))
	}
	return b.String()
}

// watch waits for the PR's checks: one more try at a failure, then the
// user's answer or the merge on its own.
func watch(cfg Config, id string) (map[string]any, error) {
	repo := ghRepo(cfg.Repo)
	r, err := findRun(0, id)
	if err != nil {
		return nil, err
	}
	editRun(id, func(r *Run) { r.Stage, r.CI = "ci", "pending" })
	start := time.Now()
	for {
		state, failed := ciState(repo, r.PR)
		if state == "pending" && time.Since(start) > 3*time.Hour {
			state = "fail"
		}
		if state == "pending" {
			time.Sleep(time.Minute)
			continue
		}
		if state == "fail" && !r.CIRetried && r.Session != "" {
			editRun(id, func(r *Run) { r.CIRetried = true })
			if r, err = retryCI(cfg, r, failedLogs(repo, failed)); err == nil {
				start = time.Now()
				time.Sleep(time.Minute)
				continue
			}
		}
		r, _ = editRun(id, func(r *Run) { r.CI, r.Stage = state, "ready" })
		break
	}
	if r.CI == "pass" && cfg.AutoMerge && r.AutoMerge {
		if err := merge(cfg, r); err == nil {
			notify("Merged on its own: "+r.Title, "Its checks passed and it only touched "+strings.Join(cfg.AutoMergePaths, ", ")+".", "low")
			return watchMain(cfg, r.ID)
		}
	}
	summary, body, actions := "Fix ready: "+r.Title, "Its checks passed.", []string{"merge=Merge", "look=Look", "drop=Drop"}
	if r.CI != "pass" {
		summary, body, actions = "A fix failed its checks: "+r.Title, "It stays open as a PR.", []string{"look=Look", "drop=Drop"}
	}
	if r.Sensitive {
		body += " It touches what agents may do: look before merging."
	}
	return answer(cfg, r, notify(summary, body+"\n"+r.URL, "normal", actions...))
}

// answer does what the user picked in a notification or Settings.
func answer(cfg Config, r Run, action string) (map[string]any, error) {
	switch action {
	case "merge":
		if err := merge(cfg, r); err != nil {
			notify("The fix didn't merge: "+r.Title, clip(err.Error(), 300), "normal")
			return nil, err
		}
		return watchMain(cfg, r.ID)
	case "drop":
		return drop(cfg, r)
	case "look":
		exec.Command("xdg-open", r.URL).Start()
	}
	return map[string]any{"run": r.ID, "action": action}, nil
}

// retryCI gives the session CI's failure, checks its new change as the
// first, and pushes it over the PR's commit.
func retryCI(cfg Config, r Run, logs string) (Run, error) {
	unlock, err := lock("run.lock", true)
	if err != nil {
		return r, err
	}
	defer unlock()
	repo := repoDir()
	if _, err := git(repo, "fetch", "origin", "main", r.Branch); err != nil {
		return r, err
	}
	if _, err := git(repo, "checkout", "--force", "-B", r.Branch, "origin/"+r.Branch); err != nil {
		return r, err
	}
	base, err := git(repo, "merge-base", "HEAD", "origin/main")
	if err != nil {
		return r, err
	}
	lim := Limits{cfg.MaxFiles, cfg.MaxLines}
	// Its change stays in the files, uncommitted: redone, it is committed
	// again whole.
	if _, err := git(repo, "reset", "--soft", base); err != nil {
		return r, err
	}
	git(repo, "reset", "--quiet")
	s, err := ask(cfg, repo, "Your change is in the working tree. CI failed on it:\n\n"+logs+
		"\nFix that (within the same rules), or answer skip.", r.Session, lim)
	editRun(r.ID, func(x *Run) { x.Cost += s.cost })
	if err != nil || s.answer.Outcome != "fixed" {
		git(repo, "checkout", "--force", "origin/"+r.Branch)
		return r, errorf("no second try: %v", err)
	}
	changes, err := diff(repo)
	if err != nil {
		return r, err
	}
	if why := checkDiff(changes, lim); len(why) > 0 {
		return r, errorf("%s", strings.Join(why, "; "))
	}
	if res := check(repo, base, changes, filepath.Join(dataDir(), "runs", r.ID)); !res.ok {
		return r, errorf("its checks: %s", firstLine(res.feedback))
	}
	var it Item
	var in Inbox
	readJSON(inboxPath(), &in)
	if p := in.find(r.Item); p != nil {
		it = *p
	}
	msg := commitMessage(s.answer, it)
	if why := checkMessage(msg); len(why) > 0 {
		return r, errorf("%s", strings.Join(why, "; "))
	}
	if _, err := cmd(repo, 10*time.Minute, msg, "git", "commit", "--quiet", "-F", "-"); err != nil {
		return r, err
	}
	if _, err := git(repo, append(ghCred, "push", "--force", "origin", "HEAD:refs/heads/"+r.Branch)...); err != nil {
		return r, err
	}
	return editRun(r.ID, func(x *Run) { x.Files, x.Title, x.CI = changes, firstLine(msg), "pending" })
}

// merge: a rebase merge, as every PR of nixbook (--admin past main's
// rules when the user may).
func merge(cfg Config, r Run) error {
	sha, err := ghMerge(ghRepo(cfg.Repo), r.PR)
	if err != nil {
		return err
	}
	r, err = editRun(r.ID, func(x *Run) { x.Outcome, x.Merged, x.Stage, x.Finished = "merged", sha, "merged", nowMs() })
	editInbox(func(in *Inbox) error {
		if p := in.find(r.Item); p != nil {
			p.Status = "merged"
		}
		return nil
	})
	return err
}

// ghMerge merges a PR: its commit on main.
func ghMerge(repo string, pr int) (string, error) {
	n := fmt.Sprint(pr)
	if _, err := gh("pr", "merge", n, "--repo", repo, "--rebase", "--admin", "--delete-branch"); err != nil {
		if _, err2 := gh("pr", "merge", n, "--repo", repo, "--rebase", "--delete-branch"); err2 != nil {
			return "", err
		}
	}
	return gh("pr", "view", n, "--repo", repo, "--json", "mergeCommit", "--jq", ".mergeCommit.oid")
}

func drop(cfg Config, r Run) (map[string]any, error) {
	if r.PR != 0 {
		if _, err := gh("pr", "close", fmt.Sprint(r.PR), "--repo", ghRepo(cfg.Repo), "--delete-branch",
			"--comment", "Dropped by the user."); err != nil {
			return nil, err
		}
	}
	r, _ = editRun(r.ID, func(x *Run) { x.Outcome, x.Stage, x.Finished = "dropped", "done", nowMs() })
	editInbox(func(in *Inbox) error {
		if p := in.find(r.Item); p != nil {
			p.Status = "dropped"
		}
		return nil
	})
	return map[string]any{"run": r.ID, "dropped": true}, nil
}

// watchMain waits for main's checks on the merged commit: failed, a revert
// is opened at once.
func watchMain(cfg Config, id string) (map[string]any, error) {
	repo := ghRepo(cfg.Repo)
	r, err := findRun(0, id)
	if err != nil || r.Merged == "" {
		return map[string]any{"run": id}, err
	}
	editRun(id, func(x *Run) { x.Stage = "main" })
	for start := time.Now(); time.Since(start) < 4*time.Hour; time.Sleep(2 * time.Minute) {
		var runs []struct{ Status, Conclusion string }
		if ghJSON(&runs, "api", fmt.Sprintf("repos/%s/commits/%s/check-runs", repo, r.Merged),
			"--jq", "[.check_runs[] | {Status: .status, Conclusion: .conclusion}]") != nil || len(runs) == 0 {
			continue
		}
		if slices.ContainsFunc(runs, func(c struct{ Status, Conclusion string }) bool { return c.Status != "completed" }) {
			continue
		}
		// Cancelled: superseded by a newer push, not failed.
		if slices.ContainsFunc(runs, func(c struct{ Status, Conclusion string }) bool {
			return c.Conclusion == "failure" || c.Conclusion == "timed_out"
		}) {
			editRun(id, func(x *Run) { x.MainCI, x.Stage = "fail", "done" })
			return revert(cfg, r, "main's checks failed after it")
		}
		editRun(id, func(x *Run) { x.MainCI, x.Stage = "pass", "done" })
		return map[string]any{"run": id, "main": "pass"}, nil
	}
	editRun(id, func(x *Run) { x.Stage = "done" })
	return map[string]any{"run": id, "main": "unknown"}, nil
}

// revert opens a PR reverting a merged fix, and merges it when the user
// says so.
func revert(cfg Config, r Run, why string) (map[string]any, error) {
	repo := ghRepo(cfg.Repo)
	unlock, err := lock("run.lock", true)
	if err != nil {
		return nil, err
	}
	branch := "agent/revert-" + r.Item
	_, err = prepare(cfg.Repo, branch)
	if err == nil {
		_, err = git(repoDir(), "revert", "--no-edit", r.Merged)
	}
	if err == nil {
		msg := fmt.Sprintf("Revert %q\n\n%s\n\nThis reverts commit %s: %s.\n\nAgent-Fix: %s\n",
			r.Title, wrap("The desktop agent's fix is taken back out until it is made again: "+why+".", 72), r.Merged, why, r.Item)
		_, err = cmd(repoDir(), time.Minute, msg, "git", "commit", "--amend", "--quiet", "-F", "-")
	}
	if err == nil {
		_, err = git(repoDir(), append(ghCred, "push", "--force", "origin", "HEAD:refs/heads/"+branch)...)
	}
	var url string
	if err == nil {
		url, err = cmd("", 2*time.Minute, fmt.Sprintf("Reverts #%d: %s.\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)\n", r.PR, why),
			"gh", "pr", "create", "--repo", repo, "--base", "main", "--head", branch,
			"--title", fmt.Sprintf("Revert %q", r.Title), "--label", "agent-fix", "--body-file", "-")
	}
	unlock()
	if err != nil {
		notify("A fix broke something: "+r.Title, why+". Reverting it failed: "+clip(err.Error(), 200), "critical")
		return nil, err
	}
	url = strings.TrimSpace(url)
	pr := atoi(url[strings.LastIndex(url, "/")+1:])
	editRun(r.ID, func(x *Run) { x.Note = why + " — revert: " + url })
	switch notify("A fix broke something: "+r.Title, why+". A revert is ready.\n"+url, "critical",
		"revert=Merge the revert", "look=Look") {
	case "revert":
		if _, err := ghMerge(repo, pr); err != nil {
			return nil, err
		}
		editRun(r.ID, func(x *Run) { x.Outcome = "reverted" })
		editInbox(func(in *Inbox) error {
			if p := in.find(r.Item); p != nil {
				p.Status, p.Note = "failed", "reverted: "+why
			}
			return nil
		})
		notify("Reverted: "+r.Title, "Update the system to take it out of this machine too.", "normal")
	case "look":
		exec.Command("xdg-open", url).Start()
	}
	return map[string]any{"run": r.ID, "revert": url}, nil
}
