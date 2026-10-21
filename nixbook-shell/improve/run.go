package main

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
	"unicode"
)

type runOpts struct {
	item   string // an inbox item ("Fix now"); else the ripest
	auto   bool   // started on its own: the day's limit applies
	noPush bool   // stop at the local commit (a dry run)
}

var errNothing = errors.New("nothing to fix")

func repoDir() string { return filepath.Join(dataDir(), "repo") }

// fetchGit: git over the network, with the token when there is one (a
// dry run reads a public repository without).
func fetchGit(dir string, args ...string) (string, error) {
	if token() == "" {
		out, err := cmd(dir, 30*time.Minute, "", "git", args...)
		return strings.TrimSpace(out), err
	}
	return gitNet(dir, args...)
}

// prepare brings the clone (of OWNER/NAME, over https) to origin/main on a
// fresh branch: its base.
func prepare(name, branch string) (string, error) {
	repo := repoDir()
	url := httpsURL(name)
	if _, err := os.Stat(filepath.Join(repo, ".git")); err != nil {
		os.RemoveAll(repo)
		if err := os.MkdirAll(filepath.Dir(repo), 0o700); err != nil {
			return "", err
		}
		if _, err := fetchGit("", "clone", "--filter=blob:none", url, repo); err != nil {
			return "", err
		}
	}
	git(repo, "remote", "set-url", "origin", url)
	if _, err := fetchGit(repo, "fetch", "--prune", "origin", "main"); err != nil {
		return "", err
	}
	git(repo, "worktree", "prune")
	if _, err := git(repo, "checkout", "--force", "-B", branch, "origin/main"); err != nil {
		return "", err
	}
	// Untracked files go, ignored ones (devenv's) stay.
	if _, err := git(repo, "clean", "-fd"); err != nil {
		return "", err
	}
	return git(repo, "rev-parse", "origin/main")
}

func run(o runOpts) (map[string]any, error) {
	cfg, err := loadConfig()
	if err != nil {
		return nil, err
	}
	if !available() {
		return nil, errUnavailable
	}
	// notStarted: no fix this time, and why (in the activity too).
	notStarted := func(why string) (map[string]any, error) {
		logEvent("wait", "No fix started: "+why)
		return map[string]any{"ran": false, "why": why}, nil
	}
	if !cfg.Enable {
		return notStarted("it's off (Settings > Desktop agents)")
	}
	if cfg.aiPolicy != 1 {
		return notStarted("AI features are off, or local models only (Settings > Desktop agents > AI features)")
	}
	if !o.noPush && token() == "" {
		logEvent("error", errNoToken.Error())
		return nil, errNoToken
	}
	unlock, err := lock("run.lock", false)
	if errors.Is(err, errBusy) {
		return map[string]any{"ran": false, "why": "a fix is already being made"}, nil
	}
	if err != nil {
		return nil, err
	}
	defer unlock()
	interrupted("interrupted")
	rs, err := readRuns()
	if err != nil {
		return nil, err
	}
	if o.auto && runsToday(rs) >= cfg.PerDay {
		return notStarted(fmt.Sprintf("today's fixes are made (%d a day; Fix now still works)", cfg.PerDay))
	}
	repoName := ghRepo(cfg.Repo)
	if repoName == "" {
		return nil, errorf("no GitHub repository: set updates.repoUrl (Settings > Services) or ai.improve.repo")
	}

	var it Item
	var waiting string
	now := nowMs()
	_, err = editInbox(func(in *Inbox) error {
		var p *Item
		if o.item != "" {
			if p = in.find(o.item); p == nil {
				return errorf("no item %s", o.item)
			}
			if p.Status == "working" || p.Status == "pr" {
				return errorf("item %s is being fixed already", o.item)
			}
		} else if p = in.pick(now); p == nil {
			waiting = waitingSummary(*in)
			return errNothing
		}
		p.Status, p.Tried, p.TriedCount = "working", now, p.Count
		it = *p
		return nil
	})
	if errors.Is(err, errNothing) {
		return notStarted(waiting)
	}
	if err != nil {
		return nil, err
	}

	id := newRunID()
	runDir := filepath.Join(dataDir(), "runs", id)
	os.MkdirAll(runDir, 0o700)
	stage := func(s string) { editRun(id, func(r *Run) { r.Stage, r.Doing = s, stageText[s] }) }
	editRun(id, func(r *Run) {
		r.Item, r.ItemText, r.Manual, r.Stage, r.Doing = it.ID, clip(it.Text, 200), !o.auto, "clone", stageText["clone"]
		r.PID = os.Getpid()
	})
	doing = doingFor(id)
	logEvent("start", "Fixing: "+clip(it.Text, 200))
	// end: the run is over, and so the item's try.
	end := func(outcome, note, status string) (map[string]any, error) {
		r, _ := editRun(id, func(r *Run) {
			r.Outcome, r.Note, r.Stage, r.Doing, r.Finished = outcome, clip(note, 600), "done", "", nowMs()
		})
		logEvent("done", outcomeText[outcome]+": "+clip(note, 300))
		editInbox(func(in *Inbox) error {
			if p := in.find(it.ID); p != nil {
				p.Status, p.Note = status, clip(note, 300)
			}
			return nil
		})
		return map[string]any{"ran": true, "run": r}, nil
	}

	branch := "agent/fix-" + it.ID
	base, err := prepare(repoName, branch)
	if err != nil {
		return end("failed", "the repository: "+err.Error(), "new")
	}
	repo := repoDir()
	lim := Limits{cfg.MaxFiles, cfg.MaxLines}

	stage("fix")
	s, err := ask(cfg, repo, firstPrompt(it, contextFor(repoName, repo, it)), "", lim)
	cost := s.cost
	editRun(id, func(r *Run) { r.Session, r.Cost = s.id, cost })
	if err != nil {
		return end("failed", err.Error(), "failed")
	}
	var changes []Change
	var res checkResult
	for try := 0; ; try++ {
		switch s.answer.Outcome {
		case "skip":
			if s.denials > 0 {
				// Not the item's fault: Claude Code refused the edits
				// (a clone in a place it guards, ~/.claude…).
				return end("failed", "Claude Code refused its edits: "+s.answer.Reason, "new")
			}
			return end("skipped", s.answer.Reason, "skipped")
		case "too_big":
			notify("Needs a real change: "+clip(it.Text, 80), clip(s.answer.Reason, 300), "low")
			return end("too_big", s.answer.Reason, "too_big")
		}
		stage("check")
		changes, err = diff(repo)
		if err != nil {
			return end("failed", err.Error(), "failed")
		}
		feedback := ""
		if why := checkDiff(changes, lim); len(why) > 0 {
			feedback = "Your change was refused, it isn't a fix:\n- " + strings.Join(why, "\n- ")
		} else if res = check(repo, base, changes, runDir); !res.ok {
			feedback = res.feedback
		}
		if feedback == "" {
			break
		}
		os.WriteFile(filepath.Join(runDir, fmt.Sprintf("feedback-%d.txt", try)), []byte(feedback), 0o600)
		if try == 1 {
			return end("failed", strings.Join(strings.Fields(feedback), " "), "failed")
		}
		logEvent("retry", "Its change didn't pass ("+clip(firstLine(feedback), 120)+"): Claude tries again")
		stage("fix")
		s, err = ask(cfg, repo, "Your change didn't pass its checks:\n\n"+feedback+
			"\nFix that (within the same rules), or answer skip or too_big.", s.id, lim)
		cost += s.cost
		editRun(id, func(r *Run) { r.Cost = cost })
		if err != nil {
			return end("failed", err.Error(), "failed")
		}
	}

	// A title too long for the changelog's line: the session shortens it
	// (one short turn) rather than having it cut mid-sentence.
	if over := titleRoom(s.answer); over < 0 && s.id != "" {
		max := len([]rune(s.answer.Title)) + over
		if s2, err := ask(cfg, repo, fmt.Sprintf("Your title is %d characters too long for the commit's first line. "+
			"Answer the same again, changing nothing in the files, with a title of at most %d characters.",
			-over, max), s.id, lim); err == nil && s2.answer.Outcome == "fixed" {
			cost += s2.cost
			s.answer.Title = s2.answer.Title
		}
		editRun(id, func(r *Run) { r.Cost = cost })
	}
	msg := commitMessage(s.answer, it)
	if why := checkMessage(msg); len(why) > 0 {
		return end("failed", "its commit message: "+strings.Join(why, "; "), "failed")
	}
	if _, err := cmd(repo, 10*time.Minute, msg, "git", unsigned("commit", "--quiet", "-F", "-")...); err != nil {
		return end("failed", "the commit: "+err.Error(), "failed")
	}
	title := firstLine(msg)
	sensitiveFiles := anySensitive(changes)
	editRun(id, func(r *Run) {
		r.Type, r.Title, r.Branch, r.Files, r.Before = s.answer.Type, title, branch, changes, res.before
		r.Sensitive, r.AutoMerge = sensitiveFiles, autoMergeWhy(cfg, changes) != ""
	})
	if o.noPush {
		return end("checked", "a dry run: committed on "+branch+" in "+repo+", not pushed", "new")
	}

	stage("push")
	if _, err := gitNet(repo, "push", "--force", "origin", "HEAD:refs/heads/"+branch); err != nil {
		return end("failed", "the push: "+err.Error(), "failed")
	}
	gh("label", "create", "agent-fix", "--repo", repoName, "--color", "C5DEF5",
		"--description", "A fix or polish made by the desktop agent (nixbook-improve)")
	url, err := ghIn(2*time.Minute, prBody(s.answer, it, res.report, changes, sensitiveFiles), "pr", "create",
		"--repo", repoName, "--base", "main", "--head", branch, "--title", title, "--label", "agent-fix", "--body-file", "-")
	if err != nil {
		if strings.Contains(err.Error(), "not accessible by personal access token") {
			return end("failed", "the token can't open pull requests: give it Pull requests: Read and write "+
				"(GitHub > Settings > Developer settings > Fine-grained tokens), then Fix now", "failed")
		}
		return end("failed", "the pull request: "+err.Error(), "failed")
	}
	url = strings.TrimSpace(url)
	pr := atoi(url[strings.LastIndex(url, "/")+1:])
	editRun(id, func(r *Run) { r.PR, r.URL, r.Outcome, r.Doing = pr, url, "pr", "" })
	logEvent("pr", fmt.Sprintf("Opened #%d: %s — CI runs now", pr, title))
	editInbox(func(in *Inbox) error {
		if p := in.find(it.ID); p != nil {
			p.Status, p.PR = "pr", pr
		}
		return nil
	})
	unlock() // the PR is out: the next run may start while CI runs
	return watch(cfg, id)
}

// interrupted ends the runs a stopped process left going (a reboot, the
// unit's time limit). Only called under the run lock: until its PR is out,
// a run holds it, so none of them is still going.
func interrupted(note string) {
	rs, err := readRuns()
	if err != nil {
		return
	}
	var items []string
	for _, r := range rs {
		if r.Outcome == "" {
			editRun(r.ID, func(x *Run) { x.Outcome, x.Note, x.Stage, x.Doing, x.Finished = "failed", note, "done", "", nowMs() })
			logEvent("done", "Stopped: "+clip(r.ItemText, 120)+" ("+note+")")
			items = append(items, r.Item)
		}
	}
	if len(items) > 0 {
		editInbox(func(in *Inbox) error {
			for _, id := range items {
				if p := in.find(id); p != nil && p.Status == "working" {
					p.Status, p.Note = "new", note
				}
			}
			return nil
		})
	}
}

// In words, for Settings and the activity.
var stageText = map[string]string{
	"clone": "Getting the repository up to date",
	"fix":   "Claude looks for the cause",
	"check": "Checking the change",
	"push":  "Pushing and opening the pull request",
}

var outcomeText = map[string]string{
	"skipped": "Skipped", "too_big": "Too big for a fix", "failed": "Failed", "checked": "Dry run done",
}

var scopeRe = regexp.MustCompile(`[^a-z0-9./-]+`)

// commitMessage: "fix(scope): title", the session's changelog entry, what
// it answers, and the trailers.
// titlePrefix: "fix(scope): " as commitMessage writes it.
func titlePrefix(a Answer) string {
	typ := a.Type
	if typ != "polish" {
		typ = "fix"
	}
	scope := strings.Trim(scopeRe.ReplaceAllString(strings.ToLower(a.Scope), "-"), "-")
	if scope == "" {
		scope = "nixbook-shell"
	}
	return typ + "(" + scope + "): "
}

// titleRoom: what is left of the 72 columns after the title (negative:
// too long).
func titleRoom(a Answer) int {
	title := strings.TrimRight(strings.TrimSpace(firstLine(a.Title)), ".")
	return 72 - len([]rune(titlePrefix(a))) - len([]rune(title))
}

func commitMessage(a Answer, it Item) string {
	prefix := titlePrefix(a)
	title := strings.TrimRight(strings.TrimSpace(firstLine(a.Title)), ".")
	if r := []rune(title); len(r) > 0 {
		r[0] = unicode.ToLower(r[0])
		title = string(r)
	}
	// Still too long (the session didn't shorten it): cut at a word,
	// without "…" (it is the changelog's line).
	if r, max := []rune(title), 72-len([]rune(prefix)); len(r) > max {
		title = string(r[:max])
		if i := strings.LastIndex(title, " "); i > max/2 {
			title = title[:i]
		}
		title = strings.TrimRight(title, " ,;:")
	}
	var b strings.Builder
	b.WriteString(prefix + title + "\n\n")
	b.WriteString(wrap(a.Body, 72) + "\n\n")
	b.WriteString(wrap(reported(it), 72) + "\n\n")
	fmt.Fprintf(&b, "Agent-Fix: %s\nCo-Authored-By: Claude <noreply@anthropic.com>\n", it.ID)
	return b.String()
}

// contextFor: what the session gets besides the item: the code at the
// revision that printed a QML warning, the failed jobs' logs of CI.
func contextFor(repoName, repo string, it Item) string {
	switch it.Kind {
	case "qml":
		return atRev(repo, it)
	case "ci":
		if it.Ref == "" {
			return ""
		}
		logs, _ := ghIn(3*time.Minute, "", "run", "view", it.Ref, "--repo", repoName, "--log-failed")
		if logs == "" {
			return ""
		}
		return "\nThe failed jobs' logs (their end):\n" + tail(logs, 6000) + "\n"
	}
	return ""
}

// reported: what the fix answers, without the user's words (the
// repository is public; the session's body says it in its own).
func reported(it Item) string {
	switch it.Kind {
	case "qml":
		return fmt.Sprintf("Seen %d times in the shell's log.", it.Count)
	case "crash":
		return fmt.Sprintf("The desktop tool crashed %d times.", it.Count)
	case "service":
		return "A unit nixbook defines had failed on the machine."
	case "log":
		return fmt.Sprintf("A unit nixbook defines logged the error %d times.", it.Count)
	case "deploy":
		return "The system update failed on the machine."
	case "warning":
		return "The system update printed a Nix warning."
	case "ci":
		return "CI failed on main."
	case "coredump":
		return fmt.Sprintf("A program nixbook packages crashed %d times.", it.Count)
	case "info":
		return "Seen on the machine; fixed on the user's request."
	}
	return "Reported by the user."
}

func prBody(a Answer, it Item, report []string, changes []Change, sensitiveFiles bool) string {
	var b strings.Builder
	b.WriteString(strings.TrimSpace(a.Body) + "\n\n")
	b.WriteString("**Why:** " + reported(it))
	if it.Kind == "qml" {
		// Paths and numbers are out of it already (normalizeMsg).
		b.WriteString(" The warning: `" + strings.ReplaceAll(it.Text, "`", "'") + "`")
	}
	b.WriteString("\n\n**Checked on the machine:**\n")
	if len(report) == 0 {
		b.WriteString("- nothing to run locally for these files (CI checks them)\n")
	}
	for _, l := range report {
		b.WriteString(l + "\n")
	}
	b.WriteString("\n**Files:**\n")
	for _, c := range changes {
		fmt.Fprintf(&b, "- `%s` (+%d −%d)\n", c.Path, c.Added, c.Deleted)
	}
	if sensitiveFiles {
		b.WriteString("\n⚠️ Touches what agents may do (their tools, permissions or switches): never merged on its own.\n")
	}
	b.WriteString("\n---\nOpened by nixbook-improve, the desktop agent's fixer: fixes and polish only, " +
		"checked by `nixbook-improve guard` in CI (agent-guard).\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)\n")
	return b.String()
}

func firstLine(s string) string {
	l, _, _ := strings.Cut(strings.TrimSpace(s), "\n")
	return strings.TrimSpace(l)
}

// wrap re-flows each paragraph to width columns; "- " and "* " lines stay
// list items, their continuation indented.
func wrap(s string, width int) string {
	var out []string
	for _, para := range strings.Split(strings.TrimSpace(s), "\n\n") {
		var lines []string
		cur, indent := "", ""
		for _, l := range strings.Split(para, "\n") {
			t := strings.TrimSpace(l)
			if strings.HasPrefix(t, "- ") || strings.HasPrefix(t, "* ") {
				if cur != "" {
					lines = append(lines, cur)
				}
				cur, indent = "", "  "
			}
			for _, w := range strings.Fields(t) {
				switch {
				case cur == "":
					cur = w
				case len([]rune(cur))+1+len([]rune(w)) > width:
					lines = append(lines, cur)
					cur = indent + w
				default:
					cur += " " + w
				}
			}
		}
		if cur != "" {
			lines = append(lines, cur)
		}
		out = append(out, strings.Join(lines, "\n"))
	}
	return strings.Join(out, "\n\n")
}
