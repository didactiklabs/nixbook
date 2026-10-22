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
	out, _ := ghIn(2*time.Minute, "", "pr", "checks", fmt.Sprint(pr), "--repo", repo, "--json", "bucket,name,link")
	if json.Unmarshal([]byte(out), &cs) != nil || len(cs) == 0 {
		return "pending", nil
	}
	state := "pass"
	var failed []ciCheck
	for _, c := range cs {
		switch c.Bucket {
		// Cancelled (superseded by a newer run) or skipped: not a failure.
		case "fail":
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
		out, _ := ghIn(3*time.Minute, "", "run", "view", m[1], "--repo", repo, "--log-failed")
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
	editRun(id, func(r *Run) { r.Stage, r.CI, r.Doing = "ci", "pending", "Waiting for CI" })
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
		logs := ""
		if state == "fail" {
			logs = failedLogs(repo, failed)
		}
		// No log to read (a runner's problem, not the change's): no retry.
		if state == "fail" && strings.TrimSpace(strings.ReplaceAll(logs, "==", "")) != "" && !r.CIRetried && r.Session != "" {
			editRun(id, func(r *Run) { r.CIRetried = true })
			logEvent("retry", fmt.Sprintf("CI failed on #%d: Claude tries again with its logs", r.PR))
			if r, err = retryCI(cfg, r, logs); err == nil {
				start = time.Now()
				time.Sleep(time.Minute)
				continue
			}
		}
		r, _ = editRun(id, func(r *Run) { r.CI, r.Stage, r.Doing = state, "ready", "" })
		if state == "pass" {
			logEvent("ci", fmt.Sprintf("CI passed on #%d: it waits for you (Merge, Look, Drop)", r.PR))
		} else {
			logEvent("ci", fmt.Sprintf("CI failed on #%d: left open for you", r.PR))
		}
		break
	}
	// GitHub's auto-merge may have merged it already.
	if r2, changed := syncRun(cfg, r); changed {
		if r2.Outcome == "merged" {
			notify("Merged on its own: "+r2.Title, "Its checks passed. Update the system to get it.", "low")
			return watchMain(cfg, r2.ID)
		}
		return map[string]any{"outcome": r2.Outcome}, nil
	}
	if r.CI != "pass" && r.AutoMerge {
		// Failed: never merged later behind the user's back (a re-run passing).
		gh("pr", "merge", fmt.Sprint(r.PR), "--repo", repo, "--disable-auto")
	}
	if why := autoMergeWhy(cfg, r.Files, r.Feature); r.CI == "pass" && why != "" {
		if err := merge(cfg, r); err == nil {
			logEvent("merged", fmt.Sprintf("Merged #%d on its own (%s)", r.PR, why))
			notify("Merged on its own: "+r.Title, "Its checks passed; "+why+". Update the system to get it.", "low")
			return watchMain(cfg, r.ID)
		}
	}
	ready := "Fix ready: "
	if r.Feature {
		ready = "Feature ready: "
	}
	summary, body, actions := ready+r.Title, "Its checks passed.", []string{"merge=Merge", "look=Look", "drop=Drop"}
	if r.CI != "pass" {
		summary, body, actions = "A "+r.noun()+" failed its checks: "+r.Title, "It stays open as a PR.", []string{"look=Look", "drop=Drop"}
	}
	if r.Sensitive {
		body += " It touches what agents may do: look before merging."
	}
	return answer(cfg, r, notify(summary, body+"\n"+r.URL, "normal", actions...))
}

// answer does what the user picked in a notification or Settings.
func answer(cfg Config, r Run, action string) (map[string]any, error) {
	// Merged or closed on GitHub meanwhile: so be it, whatever was asked.
	if action != "look" {
		if r2, changed := syncRun(cfg, r); changed {
			return map[string]any{"run": r2.ID, "outcome": r2.Outcome}, nil
		}
	}
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
	doing = doingFor(r.ID)
	defer func() { doing = func(string) {} }()
	unlock, err := lock("run.lock", true)
	if err != nil {
		return r, err
	}
	defer unlock()
	repo := repoDir()
	if _, err := gitNet(repo, "fetch", "origin", "main", r.Branch); err != nil {
		return r, err
	}
	if _, err := git(repo, "checkout", "--force", "-B", r.Branch, "origin/"+r.Branch); err != nil {
		return r, err
	}
	base, err := git(repo, "merge-base", "HEAD", "origin/main")
	if err != nil {
		return r, err
	}
	lim := cfg.limits(r.Feature)
	forFeature = r.Feature
	// Its change stays in the files, uncommitted: redone, it is committed
	// again whole.
	if _, err := git(repo, "reset", "--soft", base); err != nil {
		return r, err
	}
	git(repo, "reset", "--quiet")
	s, err := ask(cfg, repo, "Your change is in the working tree. CI failed on it:\n\n"+logs+
		"\nFix that (within the same rules), or answer skip.", r.Session, r.Feature)
	editRun(r.ID, func(x *Run) { x.Cost += s.cost })
	if err != nil || !s.answer.made() {
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
	if why := checkMessage(msg, r.Feature); len(why) > 0 {
		return r, errorf("%s", strings.Join(why, "; "))
	}
	if _, err := cmd(repo, 10*time.Minute, msg, "git", unsigned("commit", "--quiet", "-F", "-")...); err != nil {
		return r, err
	}
	if _, err := gitNet(repo, "push", "--force", "origin", "HEAD:refs/heads/"+r.Branch); err != nil {
		return r, err
	}
	return editRun(r.ID, func(x *Run) { x.Files, x.Title, x.CI = changes, firstLine(msg), "pending" })
}

// merge: a rebase merge, as every PR of nixbook, with the token.
func merge(cfg Config, r Run) error {
	sha, err := ghMerge(ghRepo(cfg.Repo), r.PR)
	if err != nil {
		return err
	}
	r, err = editRun(r.ID, func(x *Run) { x.Outcome, x.Merged, x.Stage, x.Finished = "merged", sha, "merged", nowMs() })
	logEvent("merged", fmt.Sprintf("Merged #%d: %s", r.PR, r.Title))
	editInbox(func(in *Inbox) error {
		if p := in.find(r.Item); p != nil {
			p.Status = "merged"
		}
		return nil
	})
	return err
}

// armAutoMerge sets GitHub's auto-merge on a PR (a rebase merge, its
// branch deleted): GitHub merges it once its required checks pass.
func armAutoMerge(repo string, pr int) error {
	_, err := gh("pr", "merge", fmt.Sprint(pr), "--repo", repo, "--auto", "--rebase", "--delete-branch")
	return err
}

// ghMerge merges a PR: its commit on main.
func ghMerge(repo string, pr int) (string, error) {
	n := fmt.Sprint(pr)
	if _, err := gh("pr", "merge", n, "--repo", repo, "--rebase", "--delete-branch"); err != nil {
		// Past main's rules only if the token may (an admin's: not advised).
		if _, err2 := gh("pr", "merge", n, "--repo", repo, "--rebase", "--admin", "--delete-branch"); err2 != nil {
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
	logEvent("done", fmt.Sprintf("Dropped #%d: %s", r.PR, r.Title))
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
			logEvent("revert", "main's checks failed after "+r.Title+": a revert is opened")
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
	forFeature = r.Feature
	repo := ghRepo(cfg.Repo)
	unlock, err := lock("run.lock", true)
	if err != nil {
		return nil, err
	}
	branch := "agent/revert-" + r.Item
	_, err = prepare(repo, branch)
	if err == nil {
		_, err = git(repoDir(), unsigned("revert", "--no-edit", r.Merged)...)
	}
	if err == nil {
		trailer := "Agent-Fix"
		if r.Feature {
			trailer = "Agent-Feature"
		}
		msg := fmt.Sprintf("Revert %q\n\n%s\n\nThis reverts commit %s: %s.\n\n%s: %s\n",
			r.Title, wrap("The desktop agent's "+r.noun()+" is taken back out until it is made again: "+why+".", 72), r.Merged, why, trailer, r.Item)
		_, err = cmd(repoDir(), time.Minute, msg, "git", unsigned("commit", "--amend", "--quiet", "-F", "-")...)
	}
	if err == nil {
		_, err = gitNet(repoDir(), "push", "--force", "origin", "HEAD:refs/heads/"+branch)
	}
	var url string
	if err == nil {
		url, err = ghIn(2*time.Minute, fmt.Sprintf("Reverts #%d: %s.\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)\n", r.PR, why),
			"pr", "create", "--repo", repo, "--base", "main", "--head", branch,
			"--title", fmt.Sprintf("Revert %q", r.Title), "--label", "agent-fix", "--body-file", "-")
	}
	unlock()
	if err != nil {
		notify("A "+r.noun()+" broke something: "+r.Title, why+". Reverting it failed: "+clip(err.Error(), 200), "critical")
		return nil, err
	}
	url = strings.TrimSpace(url)
	pr := atoi(url[strings.LastIndex(url, "/")+1:])
	editRun(r.ID, func(x *Run) { x.Note = why + " — revert: " + url })
	logEvent("revert", fmt.Sprintf("%s broke something (%s): revert #%d is ready", r.Title, why, pr))
	switch notify("A "+r.noun()+" broke something: "+r.Title, why+". A revert is ready.\n"+url, "critical",
		"revert=Merge the revert", "look=Look") {
	case "revert":
		if _, err := ghMerge(repo, pr); err != nil {
			return nil, err
		}
		editRun(r.ID, func(x *Run) { x.Outcome = "reverted" })
		logEvent("revert", "Reverted: "+r.Title)
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

// syncRun learns what became of an open PR on GitHub (merged or closed by
// the user there): merged, it is watched as if merged here; closed, dropped.
// changed: it was.
func syncRun(cfg Config, r Run) (Run, bool) {
	if r.Outcome != "pr" || r.PR == 0 {
		return r, false
	}
	var pr struct {
		State       string `json:"state"`
		MergeCommit struct {
			Oid string `json:"oid"`
		} `json:"mergeCommit"`
	}
	if ghJSON(&pr, "pr", "view", fmt.Sprint(r.PR), "--repo", ghRepo(cfg.Repo), "--json", "state,mergeCommit") != nil {
		return r, false
	}
	switch pr.State {
	case "MERGED":
		r, _ = editRun(r.ID, func(x *Run) {
			x.Outcome, x.Merged, x.Stage, x.Doing, x.Finished = "merged", pr.MergeCommit.Oid, "merged", "", nowMs()
		})
		logEvent("merged", fmt.Sprintf("#%d was merged on GitHub: %s", r.PR, r.Title))
		editInbox(func(in *Inbox) error {
			if p := in.find(r.Item); p != nil {
				p.Status = "merged"
			}
			return nil
		})
		return r, true
	case "CLOSED":
		r, _ = editRun(r.ID, func(x *Run) { x.Outcome, x.Stage, x.Doing, x.Finished = "dropped", "done", "", nowMs() })
		logEvent("done", fmt.Sprintf("#%d was closed on GitHub: %s", r.PR, r.Title))
		editInbox(func(in *Inbox) error {
			if p := in.find(r.Item); p != nil {
				p.Status = "dropped"
			}
			return nil
		})
		return r, true
	}
	return r, false
}

// syncPRs: every open PR's fate on GitHub (sync, collect).
func syncPRs(cfg Config) int {
	if token() == "" || ghRepo(cfg.Repo) == "" {
		return 0
	}
	rs, err := readRuns()
	if err != nil {
		return 0
	}
	n := 0
	for _, r := range rs {
		if _, changed := syncRun(cfg, r); changed {
			n++
		}
	}
	return n
}
