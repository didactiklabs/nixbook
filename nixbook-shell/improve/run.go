package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"
	"unicode"
)

type runOpts struct {
	item   string // an inbox item ("Fix now", "Build now"); else the ripest
	auto   bool   // started on its own: the days' limits apply
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
	// notStarted: no fix nor feature this time, and why (in the activity too).
	notStarted := func(why string) (map[string]any, error) {
		logEvent("wait", "Nothing started: "+why)
		return map[string]any{"ran": false, "why": why}, nil
	}
	if !cfg.Enable && !cfg.Features.Enable {
		return notStarted("it's off (Settings > Desktop agents)")
	}
	if cfg.aiPolicy != 1 {
		return notStarted("AI features are off, or local models only (Settings > Desktop agents > AI features)")
	}
	if !o.noPush && token() == "" {
		logEvent("error", errNoToken.Error())
		return nil, errNoToken
	}
	unlockRun, err := lock("run.lock", false)
	if errors.Is(err, errBusy) {
		if o.item != "" {
			// Fix now / Build now while another is made: its turn comes.
			return queueItem(cfg, o.item)
		}
		return map[string]any{"ran": false, "why": "a fix is already being made"}, nil
	}
	if err != nil {
		return nil, err
	}
	// Letting go of the run lock (its PR out, or the run over) starts the
	// next queued item, in a unit of its own (a dry run starts none).
	var released sync.Once
	unlock := func() {
		released.Do(func() {
			unlockRun()
			if !o.noPush {
				startQueued(cfg)
			}
		})
	}
	defer unlock()
	interrupted("interrupted")
	// Started on its own: what waits in the queue first (asked by the user,
	// so past the day's limit as Fix now is); a stop or a reboot left it.
	if o.auto && o.item == "" {
		var in Inbox
		readJSON(inboxPath(), &in)
		if p := in.nextQueued(cfg); p != nil {
			o.item, o.auto = p.ID, false
		}
	}
	rs, err := readRuns()
	if err != nil {
		return nil, err
	}
	// Room left today: fixes first, then features, each switched on apart.
	fixRoom := cfg.Enable && (!o.auto || cfg.room(rs, false))
	featRoom := cfg.Features.Enable && (!o.auto || cfg.room(rs, true))
	if o.auto && !fixRoom && !featRoom {
		switch {
		case cfg.Enable && cfg.Features.Enable:
			return notStarted(fmt.Sprintf("today's fixes (%d a day) and features (%d a day) are made; Fix now and Build now still work",
				cfg.PerDay, cfg.Features.PerDay))
		case cfg.Features.Enable:
			return notStarted(fmt.Sprintf("today's features are made (%d a day; Build now still works)", cfg.Features.PerDay))
		}
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
			if p.Status == "unable" {
				// Retry: the user wants it tried again, from scratch.
				p.Attempts = 0
			}
			if !cfg.on(p.feature()) {
				if p.feature() {
					return errorf("building features is off (Settings > Desktop agents > Features it builds)")
				}
				return errorf("making fixes is off (Settings > Desktop agents > Fixes it makes itself)")
			}
		} else {
			if fixRoom {
				p = in.pick(now, false)
			}
			if p == nil && featRoom {
				p = in.pick(now, true)
			}
			if p == nil {
				waiting = waitingSummary(*in)
				return errNothing
			}
		}
		p.Status, p.Tried, p.TriedCount, p.Queued = "working", now, p.Count, 0
		it = *p
		return nil
	})
	if errors.Is(err, errNothing) {
		return notStarted(waiting)
	}
	if err != nil {
		return nil, err
	}

	feature := it.feature()
	forFeature = feature
	id := newRunID()
	runDir := filepath.Join(dataDir(), "runs", id)
	os.MkdirAll(runDir, 0o700)
	stage := func(s string) { editRun(id, func(r *Run) { r.Stage, r.Doing = s, stageText[s] }) }
	work := "fix"
	if feature {
		work = "build"
	}
	editRun(id, func(r *Run) {
		r.Item, r.ItemText, r.Manual, r.Stage, r.Doing = it.ID, clip(it.Text, 200), !o.auto, "clone", stageText["clone"]
		r.Feature, r.PID = feature, os.Getpid()
	})
	doing = doingFor(id)
	if feature {
		logEvent("start", "Building: "+clip(it.Text, 200))
	} else {
		logEvent("start", "Fixing: "+clip(it.Text, 200))
	}
	// end: the run is over, and so the item's try. Given up (unable: the
	// session can't, or its change failed maxAttempts times), the user is
	// told and asked what to do, the run lock let go first.
	end := func(outcome, note, status string) (map[string]any, error) {
		var gaveUp *Item
		editInbox(func(in *Inbox) error {
			if p := in.find(it.ID); p != nil {
				if status == "attempt" {
					p.Attempts++
					status = "failed"
					if p.Attempts >= maxAttempts {
						status, note = "unable", fmt.Sprintf("its change failed %d times: %s", p.Attempts, note)
					}
				} else if status != "new" {
					p.Attempts = 0
				}
				p.Status, p.Note = status, clip(note, 300)
				if status == "unable" {
					c := *p
					gaveUp = &c
				}
			}
			return nil
		})
		if status == "attempt" {
			status = "failed"
		}
		if status == "unable" {
			// Not counted in the day's runs.
			outcome = "unable"
		}
		r, _ := editRun(id, func(r *Run) {
			r.Outcome, r.Note, r.Stage, r.Doing, r.Finished = outcome, clip(note, 600), "done", "", nowMs()
		})
		logEvent("done", outcomeText[outcome]+": "+clip(note, 300))
		if gaveUp != nil {
			unlock()
			cantDo(*gaveUp, note)
		}
		return map[string]any{"ran": true, "run": r}, nil
	}

	branch := "agent/fix-" + it.ID
	if feature {
		branch = "agent/feature-" + it.ID
	}
	base, err := prepare(repoName, branch)
	if err != nil {
		return end("failed", "the repository: "+err.Error(), "new")
	}
	repo := repoDir()
	lim := cfg.limits(feature)

	stage(work)
	s, err := ask(cfg, repo, firstPrompt(it, contextFor(repoName, repo, it)), "", feature)
	cost := s.cost
	editRun(id, func(r *Run) { r.Session, r.Cost = s.id, cost })
	if err != nil {
		return end("failed", err.Error(), "attempt")
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
			if s.answer.Harmless {
				// Nothing to fix and no harm left: out of the list for good.
				return end("ignored", s.answer.Reason, "ignored")
			}
			return end("skipped", s.answer.Reason, "skipped")
		case "too_big":
			if !feature {
				// More than a fix: a feature request, built apart (when the
				// user has features on) with what the session found.
				editInbox(func(in *Inbox) error {
					_, err := in.toFeature(it.ID, s.answer.Reason, nowMs())
					return err
				})
				notify("Too big for a fix, now a feature request: "+clip(it.Text, 80), clip(s.answer.Reason, 300), "low")
				return end("too_big", "moved to the feature requests: "+s.answer.Reason, "feature")
			}
			// Too big even for a feature: given up, the user told.
			return end("too_big", s.answer.Reason, "unable")
		case "cant":
			return end("unable", s.answer.Reason, "unable")
		}
		stage("check")
		changes, err = diff(repo)
		if err != nil {
			return end("failed", err.Error(), "failed")
		}
		feedback := ""
		if why := checkDiff(changes, lim); len(why) > 0 {
			feedback = "Your change was refused:\n- " + strings.Join(why, "\n- ")
		} else if res = check(repo, base, changes, runDir); !res.ok {
			feedback = res.feedback
		}
		if feedback == "" {
			break
		}
		os.WriteFile(filepath.Join(runDir, fmt.Sprintf("feedback-%d.txt", try)), []byte(feedback), 0o600)
		if try == 1 {
			return end("failed", strings.Join(strings.Fields(feedback), " "), "attempt")
		}
		logEvent("retry", "Its change didn't pass ("+clip(firstLine(feedback), 120)+"): Muse tries again")
		stage(work)
		s, err = ask(cfg, repo, "Your change didn't pass its checks:\n\n"+feedback+
			"\nFix that (within the same rules), or answer skip or too_big.", s.id, feature)
		cost += s.cost
		editRun(id, func(r *Run) { r.Cost = cost })
		if err != nil {
			return end("failed", err.Error(), "attempt")
		}
	}

	// A title too long for the changelog's line: the session shortens it
	// (one short turn) rather than having it cut mid-sentence.
	if over := titleRoom(s.answer); over < 0 && s.id != "" {
		max := len([]rune(s.answer.Title)) + over
		if s2, err := ask(cfg, repo, fmt.Sprintf("Your title is %d characters too long for the commit's first line. "+
			"Answer the same again, changing nothing in the files, with a title of at most %d characters.",
			-over, max), s.id, feature); err == nil && s2.answer.made() {
			cost += s2.cost
			s.answer.Title = s2.answer.Title
		}
		editRun(id, func(r *Run) { r.Cost = cost })
	}
	msg := commitMessage(s.answer, it)
	if why := checkMessage(msg, feature); len(why) > 0 {
		return end("failed", "its commit message: "+strings.Join(why, "; "), "attempt")
	}
	if _, err := cmd(repo, 10*time.Minute, msg, "git", unsigned("commit", "--quiet", "-F", "-")...); err != nil {
		return end("failed", "the commit: "+err.Error(), "failed")
	}
	title := firstLine(msg)
	sensitiveFiles := anySensitive(changes)
	editRun(id, func(r *Run) {
		r.Type, r.Title, r.Branch, r.Files, r.Before = s.answer.Type, title, branch, changes, res.before
		r.Sensitive, r.AutoMerge = sensitiveFiles, autoMergeWhy(cfg, changes, feature) != ""
	})
	if o.noPush {
		return end("checked", "a dry run: committed on "+branch+" in "+repo+", not pushed", "new")
	}

	stage("push")
	if _, err := gitNet(repo, "push", "--force", "origin", "HEAD:refs/heads/"+branch); err != nil {
		return end("failed", "the push: "+err.Error(), "failed")
	}
	label := "agent-fix"
	if feature {
		label = "agent-feature"
		gh("label", "create", label, "--repo", repoName, "--color", "D4C5F9",
			"--description", "A feature the user asked the desktop agent for (nixbook-improve)")
	} else {
		gh("label", "create", label, "--repo", repoName, "--color", "C5DEF5",
			"--description", "A fix or polish made by the desktop agent (nixbook-improve)")
	}
	url, err := ghIn(2*time.Minute, prBody(s.answer, it, res.report, changes, sensitiveFiles), "pr", "create",
		"--repo", repoName, "--base", "main", "--head", branch, "--title", title, "--label", label, "--body-file", "-")
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
	// Allowed to merge on its own (the user's switch): GitHub's auto-merge,
	// set at once, merges it as soon as the required checks pass, even if
	// this process is gone by then; watch still merges it itself once CI
	// passes, if GitHub hasn't.
	then := ""
	if autoMergeWhy(cfg, changes, feature) != "" {
		if err := armAutoMerge(repoName, pr); err != nil {
			then = " (auto-merge not set: " + clip(err.Error(), 120) + "; merged here once CI passes)"
		} else {
			then = ", auto-merge set: GitHub merges it once its checks pass"
		}
	}
	logEvent("pr", fmt.Sprintf("Opened #%d: %s — CI runs now%s", pr, title, then))
	editInbox(func(in *Inbox) error {
		if p := in.find(it.ID); p != nil {
			p.Status, p.PR = "pr", pr
		}
		return nil
	})
	unlock() // the PR is out: the next run may start while CI runs
	return watch(cfg, id)
}

// queueItem puts an item asked for while another is being made in the
// queue: it starts when its turn comes.
func queueItem(cfg Config, id string) (map[string]any, error) {
	var it Item
	pos, again := 0, false
	_, err := editInbox(func(in *Inbox) error {
		p := in.find(id)
		if p == nil {
			return errorf("no item %s", id)
		}
		if p.Status == "working" || p.Status == "pr" {
			return errorf("item %s is being fixed already", id)
		}
		if !cfg.on(p.feature()) {
			if p.feature() {
				return errorf("building features is off (Settings > Desktop agents > Features it builds)")
			}
			return errorf("making fixes is off (Settings > Desktop agents > Fixes it makes itself)")
		}
		was := p.Queued
		var err error
		if pos, err = in.enqueue(id, nowMs()); err != nil {
			return err
		}
		it, again = *p, was > 0
		return nil
	})
	if err != nil {
		return nil, err
	}
	if !again {
		forFeature = it.feature()
		logEvent("wait", fmt.Sprintf("Queued (#%d): %s", pos, clip(it.Text, 200)))
	}
	return map[string]any{
		"ran": false, "queued": pos,
		"why": fmt.Sprintf("queued (#%d): it starts once the one being made is done", pos),
	}, nil
}

// startQueued starts the first queued item in a unit of its own, as the
// shell starts a run (lowest priority, this process's PATH and Claude
// Code). Its run takes it out of the queue; one that finds the run lock
// taken again keeps its place. NIXBOOK_IMPROVE_SPAWN in tests: a command
// given "run --item ID" instead.
func startQueued(cfg Config) {
	defer func(f bool) { forFeature = f }(forFeature)
	var in Inbox
	if readJSON(inboxPath(), &in) != nil {
		return
	}
	p := in.nextQueued(cfg)
	if p == nil {
		return
	}
	// The one on PATH: this process may be an older build, after an update.
	self, err := exec.LookPath("nixbook-improve")
	if err != nil {
		if self, err = os.Executable(); err != nil {
			self = "nixbook-improve"
		}
	}
	var c *exec.Cmd
	if spawn := os.Getenv("NIXBOOK_IMPROVE_SPAWN"); spawn != "" {
		c = exec.Command(spawn, "run", "--item", p.ID)
	} else {
		args := []string{
			"--user", "--collect", "--quiet", fmt.Sprintf("--unit=nixbook-improve-run-%d", nowMs()),
			"-p", "RuntimeMaxSec=8h", "-p", "Nice=19", "-p", "CPUWeight=idle", "-p", "IOSchedulingClass=idle",
			"--setenv=PATH=" + os.Getenv("PATH"),
		}
		if claude := os.Getenv("NIXBOOK_IMPROVE_CLAUDE"); claude != "" {
			args = append(args, "--setenv=NIXBOOK_IMPROVE_CLAUDE="+claude)
		}
		c = exec.Command("systemd-run", append(args, self, "run", "--item", p.ID)...)
	}
	forFeature = p.feature()
	if out, err := c.CombinedOutput(); err != nil {
		logEvent("error", fmt.Sprintf("The next in the queue didn't start: %s", clip(strings.TrimSpace(string(out))+" "+err.Error(), 200)))
		return
	}
	logEvent("start", "Next in the queue: "+clip(p.Text, 200))
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
			forFeature = r.Feature
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
	"fix":   "Muse looks for the cause",
	"build": "Muse builds the feature",
	"check": "Checking the change",
	"push":  "Pushing and opening the pull request",
}

var outcomeText = map[string]string{
	"skipped": "Skipped", "ignored": "Ignored, harmless", "too_big": "Too big", "failed": "Failed", "checked": "Dry run done",
	"unable": "Couldn't do it",
}

// cantDo tells the user an item was given up and does what they pick:
// Retry (a run at once, not counted in the day's), As a feature (a fix),
// Dismiss (dropped). Left unanswered, it waits in Settings' Dropped list
// with the same buttons.
func cantDo(it Item, reason string) {
	actions := []string{"retry=Retry"}
	if !it.feature() {
		actions = append(actions, "feature=As a feature")
	}
	actions = append(actions, "dismiss=Dismiss")
	switch notify("Couldn't do: "+clip(firstLine(it.Text), 80), clip(reason, 400), "normal", actions...) {
	case "retry":
		run(runOpts{item: it.ID})
	case "feature":
		editInbox(func(in *Inbox) error {
			_, err := in.toFeature(it.ID, reason, nowMs())
			return err
		})
	case "dismiss":
		editInbox(func(in *Inbox) error {
			if p := in.find(it.ID); p != nil && p.Status == "unable" {
				p.Status = "dropped"
			}
			return nil
		})
	}
}

var scopeRe = regexp.MustCompile(`[^a-z0-9./-]+`)

// commitMessage: "fix(scope): title" (feat for a feature), the session's
// changelog entry, what it answers, and the trailers.
// titlePrefix: "fix(scope): " as commitMessage writes it.
func titlePrefix(a Answer) string {
	typ := a.Type
	if typ != "polish" && typ != "feat" {
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
	trailer := "Agent-Fix"
	if it.feature() {
		trailer = "Agent-Feature"
	}
	fmt.Fprintf(&b, "%s: %s\nCo-Authored-By: Claude <noreply@anthropic.com>\n", trailer, it.ID)
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
	case "regression":
		return "A change merged lately broke it; fixed forward."
	case "feature":
		if it.From != "" {
			return "Too big for a fix; built as a feature."
		}
		return "Requested by the user."
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
	if it.feature() {
		b.WriteString("\n---\nOpened by nixbook-improve, the desktop agent: a feature asked for, never merged on its own, " +
			"checked by `nixbook-improve guard --feature` in CI (agent-guard).\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)\n")
	} else {
		b.WriteString("\n---\nOpened by nixbook-improve, the desktop agent's fixer: fixes and polish only, " +
			"checked by `nixbook-improve guard` in CI (agent-guard).\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)\n")
	}
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
