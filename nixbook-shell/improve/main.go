// nixbook-improve: the desktop agent fixing nixbook itself: fixes and
// polish, and apart from them the features the user asks for. What to do
// comes in an inbox (what the user reported or asked for, the shell's QML
// errors, the desktop tools' crashes, fixes found too big); a Claude Code
// session confined to a clone of the repository makes the change; this program
// checks it (size and paths, the tests, the shell started headless), commits
// it with a changelog entry, opens a PR and, once CI passes, asks the user
// (Merge, Look, Drop) or merges a fix on its own (low-risk files only;
// never a feature). Then
// main's checks and the deployed shell are watched: what a merge broke is
// filed to be fixed forward, never reverted. What it can't do is given up
// (unable), the user told, with Retry.
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"slices"
	"strings"
	"syscall"
)

const usage = `nixbook-improve: the desktop agent's fixes and features to nixbook (Settings > Desktop agents)

  nixbook-improve status                 the inbox, the runs, today's count, whether it is on
  nixbook-improve note TEXT [--where W]  something to fix, from the user (an agent's
                                         report_problem, Settings)
  nixbook-improve request TEXT [--where W]
                                         a feature to build, from the user (an agent's
                                         request_feature, Settings)
  nixbook-improve to-feature ID          move a fix item to the feature requests
  nixbook-improve drop-item ID           forget an inbox item (Dismiss of one given up)
  nixbook-improve collect                file the shell's QML errors and the desktop tools'
                                         crashes since the last time (no model)
  nixbook-improve run [--item ID] [--auto] [--no-push]
                                         fix the ripest item (or ID; a feature request
                                         builds it; one given up is tried again from
                                         scratch: Retry): the session, the checks, the
                                         commit, the PR, then CI and the user's answer;
                                         --auto: the days' limits apply (fixes first,
                                         then features; perDay 0: no limit but each
                                         run's budget); --no-push: stop at the local
                                         commit. With a run going on, --item ID is
                                         queued instead; each run, letting go, starts
                                         the next queued one (--auto takes it first)
  nixbook-improve queue ID               queue ID (without starting it when nothing runs)
  nixbook-improve unqueue ID             take ID out of the queue
  nixbook-improve queue-move ID up|down  move ID up or down the queue
  nixbook-improve stop                   stop the fix being made (Settings' Stop); the
                                         queue goes on
  nixbook-improve sync                   learn which open PRs were merged or closed on GitHub
  nixbook-improve merge|drop|look PR     what the notification's buttons do
  nixbook-improve token set|forget|status
                                         its GitHub token (set: on stdin, checked on the
                                         repository, kept in the keyring): the only
                                         credential it uses, never the user's gh or ssh
  nixbook-improve health REV             the shell running a deployed fix (REV: the
                                         deployed revision): what it broke filed to be
                                         fixed forward (never a revert)
  nixbook-improve guard BASE [HEAD] [--feature] [--max-files N] [--max-lines N]
                                         CI's agent-guard: an agent/ branch's commits are
                                         fixes, or features with --feature (paths, size,
                                         messages)

Only where Nix made it available (programs.nixbook-shell.selfImprove.enable:
"improve" in desktop-mcp.json); guard and status run anywhere.
Every command prints JSON. State: $XDG_STATE_HOME/nixbook-shell/improve/,
the clone and logs: $XDG_DATA_HOME/nixbook-shell/improve/.`

func main() {
	out, err := dispatch(os.Args[1:])
	if err != nil && len(os.Args) > 1 && slices.Contains([]string{"run", "collect", "health", "merge", "drop"}, os.Args[1]) {
		logEvent("error", os.Args[1]+": "+err.Error())
	}
	if err != nil {
		emit(map[string]any{"error": err.Error()})
		os.Exit(1)
	}
	if out != nil {
		emit(out)
	}
}

func emit(v any) {
	enc := json.NewEncoder(os.Stdout)
	enc.SetEscapeHTML(false)
	_ = enc.Encode(v)
}

// flag takes `name value` out of args.
func flag(args *[]string, name string) (string, error) {
	i := slices.Index(*args, name)
	if i < 0 {
		return "", nil
	}
	if i+1 >= len(*args) {
		return "", errorf("%s needs a value", name)
	}
	v := (*args)[i+1]
	*args = slices.Delete(*args, i, i+2)
	return v, nil
}

func boolFlag(args *[]string, name string) bool {
	i := slices.Index(*args, name)
	if i >= 0 {
		*args = slices.Delete(*args, i, i+1)
	}
	return i >= 0
}

func dispatch(args []string) (any, error) {
	if len(args) == 0 || args[0] == "-h" || args[0] == "--help" || args[0] == "help" {
		fmt.Println(usage)
		return nil, nil
	}
	cmdName, args := args[0], args[1:]
	// The guard is CI's; status says whether it is available.
	if cmdName != "guard" && cmdName != "status" && !available() {
		return nil, errUnavailable
	}
	switch cmdName {
	case "token":
		return tokenCmd(args)
	case "status":
		return status()
	case "stop":
		return stop()
	case "sync":
		cfg, err := loadConfig()
		if err != nil {
			return nil, err
		}
		return map[string]any{"changed": syncPRs(cfg)}, nil
	case "note", "request":
		where, err := flag(&args, "--where")
		if err != nil {
			return nil, err
		}
		text := strings.TrimSpace(strings.Join(args, " "))
		kind, empty := "user", "say what to fix"
		if cmdName == "request" {
			kind, empty = "feature", "say what to build"
		}
		if text == "" {
			return nil, errorf("%s", empty)
		}
		var it Item
		_, err = editInbox(func(in *Inbox) error {
			// The same words again count up instead of adding an item.
			key := kind + ":" + strings.ToLower(strings.Join(strings.Fields(text), " "))
			it = *in.add(kind, clip(key, 200), text, clip(where, 200), 1, nowMs())
			return nil
		})
		return it, err
	case "to-feature":
		if len(args) != 1 {
			return nil, errorf("to-feature ID")
		}
		var it Item
		_, err := editInbox(func(in *Inbox) error {
			old := in.find(args[0])
			why := ""
			if old != nil && old.Status == "working" {
				return errorf("item %s is being fixed", args[0])
			}
			if old != nil && old.Status == "too_big" {
				why = old.Note
			}
			f, err := in.toFeature(args[0], why, nowMs())
			if err == nil {
				it = *f
			}
			return err
		})
		return it, err
	case "queue", "unqueue", "queue-move":
		if len(args) < 1 || (cmdName == "queue-move") != (len(args) == 2) || len(args) > 2 {
			return nil, errorf("queue ID | unqueue ID | queue-move ID up|down")
		}
		cfg, err := loadConfig()
		if err != nil {
			return nil, err
		}
		if cmdName == "queue" {
			// Asked to start while one is made: as run --item, without
			// starting it now when nothing is.
			return queueItem(cfg, args[0])
		}
		in, err := editInbox(func(in *Inbox) error {
			it := in.find(args[0])
			if it == nil {
				return errorf("no item %s", args[0])
			}
			if cmdName == "unqueue" {
				it.Queued = 0
				return nil
			}
			if args[1] != "up" && args[1] != "down" {
				return errorf("queue-move ID up|down")
			}
			by := 1
			if args[1] == "up" {
				by = -1
			}
			return in.moveQueued(args[0], by)
		})
		if err != nil {
			return nil, err
		}
		q := []string{}
		for _, it := range in.queue() {
			q = append(q, it.ID)
		}
		return map[string]any{"queue": q}, nil
	case "drop-item":
		if len(args) != 1 {
			return nil, errorf("drop-item ID")
		}
		_, err := editInbox(func(in *Inbox) error {
			it := in.find(args[0])
			if it == nil {
				return errorf("no item %s", args[0])
			}
			it.Status, it.Queued = "dropped", 0
			return nil
		})
		return map[string]any{"dropped": args[0]}, err
	case "collect":
		return collect()
	case "run":
		item, err := flag(&args, "--item")
		if err != nil {
			return nil, err
		}
		return run(runOpts{item: item, auto: boolFlag(&args, "--auto"), noPush: boolFlag(&args, "--no-push")})
	case "merge", "drop", "look":
		if len(args) != 1 || atoi(args[0]) == 0 {
			return nil, errorf("%s PR", cmdName)
		}
		cfg, err := loadConfig()
		if err != nil {
			return nil, err
		}
		r, err := findRun(atoi(args[0]), "")
		if err != nil {
			return nil, err
		}
		forFeature = r.Feature
		return answer(cfg, r, cmdName)
	case "health":
		if len(args) != 1 {
			return nil, errorf("health REV")
		}
		return health(args[0])
	case "guard":
		return guardCmd(args)
	}
	return nil, errorf("unknown command %q (nixbook-improve help)", cmdName)
}

// stop ends the fix being made (before its PR is out): its process
// stopped, its run marked so.
func stop() (any, error) {
	rs, err := readRuns()
	if err != nil {
		return nil, err
	}
	for _, r := range rs {
		// Still nixbook-improve (after a reboot the pid is someone else's).
		cmdline, _ := os.ReadFile(fmt.Sprintf("/proc/%d/cmdline", r.PID))
		if r.Outcome == "" && r.PID > 0 && strings.Contains(string(cmdline), "nixbook-improve") {
			// Its whole process group: the Claude session and the checks too.
			syscall.Kill(-r.PID, syscall.SIGTERM)
			syscall.Kill(r.PID, syscall.SIGTERM)
		}
	}
	unlock, err := lock("run.lock", true)
	if err != nil {
		return nil, err
	}
	interrupted("stopped by you")
	unlock()
	// Only that one: the queue goes on.
	if cfg, err := loadConfig(); err == nil {
		startQueued(cfg)
	}
	return map[string]any{"stopped": true}, nil
}

func status() (any, error) {
	cfg, err := loadConfig()
	if err != nil {
		return nil, err
	}
	var in Inbox
	if err := readJSON(inboxPath(), &in); err != nil {
		return nil, err
	}
	rs, err := readRuns()
	if err != nil {
		return nil, err
	}
	// The limits in effect (perDay 0: none, each run's budgetUsd only).
	return map[string]any{
		"available": available(), "token": available() && token() != "",
		"enable": cfg.Enable, "repo": ghRepo(cfg.Repo), "claude": cfg.claude != "",
		"today": runsToday(rs, false), "perDay": cfg.PerDay, "unlimited": cfg.PerDay == 0, "budgetUsd": cfg.BudgetUsd,
		"inbox": in.Items, "runs": rs,
		"features": map[string]any{
			"enable": cfg.Features.Enable, "today": runsToday(rs, true), "perDay": cfg.Features.PerDay,
			"unlimited": cfg.Features.PerDay == 0, "budgetUsd": cfg.Features.BudgetUsd,
		},
	}, nil
}

// guardCmd checks BASE..HEAD of the repository in the working directory as
// run() checks a change before pushing it: a fix's limits, a feature's with
// --feature (CI passes it for agent/feature- branches). A branch of reverts
// this program made is only checked for its paths.
func guardCmd(args []string) (any, error) {
	files, err := flag(&args, "--max-files")
	if err != nil {
		return nil, err
	}
	lines, err := flag(&args, "--max-lines")
	if err != nil {
		return nil, err
	}
	feature := boolFlag(&args, "--feature")
	lim := defaults().limits(feature)
	if files != "" {
		lim.Files = atoi(files)
	}
	if lines != "" {
		lim.Lines = atoi(lines)
	}
	if len(args) < 1 || len(args) > 2 {
		return nil, errorf("guard BASE [HEAD] [--feature]")
	}
	base, head := args[0], "HEAD"
	if len(args) == 2 {
		head = args[1]
	}
	rng := base + "..." + head
	num, err := git(".", "diff", "--numstat", "--no-renames", rng)
	if err != nil {
		return nil, err
	}
	names, err := git(".", "diff", "--name-status", "--no-renames", rng)
	if err != nil {
		return nil, err
	}
	log, err := git(".", "log", "--format=%B%x00", base+".."+head)
	if err != nil {
		return nil, err
	}
	var why []string
	reverts := 0
	var msgs []string
	for _, msg := range strings.Split(log, "\x00") {
		if msg = strings.TrimSpace(msg); msg != "" {
			msgs = append(msgs, msg)
		}
	}
	for _, msg := range msgs {
		var bad []string
		if revertTitleRe.MatchString(msg) {
			// A revert this program made: its trailer only.
			reverts++
			if !anyTrailerRe.MatchString(msg) {
				bad = []string{"no Agent-Fix: or Agent-Feature: trailer"}
			}
		} else {
			bad = checkMessage(msg, feature)
		}
		for _, b := range bad {
			why = append(why, fmt.Sprintf("commit %q: %s", firstLine(msg), b))
		}
	}
	if changes := parseDiff(num, names); len(msgs) > 0 && reverts == len(msgs) {
		why = append(checkReverts(changes), why...)
	} else {
		why = append(checkDiff(changes, lim), why...)
	}
	if len(why) > 0 {
		emit(map[string]any{"ok": false, "why": why})
		os.Exit(1)
	}
	return map[string]any{"ok": true}, nil
}
