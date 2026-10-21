// nixbook-improve: the desktop agent fixing nixbook itself, fixes and
// polish only. What to fix comes in an inbox (what the user reported, the
// shell's QML errors, the desktop tools' crashes); a Claude Code session
// confined to a clone of the repository makes the change; this program
// checks it (size and paths, the tests, the shell started headless), commits
// it with a changelog entry, opens a PR and, once CI passes, asks the user
// (Merge, Look, Drop) or merges it on its own (low-risk files only). Then
// main's checks and the deployed shell are watched, and a revert offered.
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"slices"
	"strings"
)

const usage = `nixbook-improve: the desktop agent's fixes to nixbook (Settings > Desktop agents)

  nixbook-improve status                 the inbox, the runs, today's count, whether it is on
  nixbook-improve note TEXT [--where W]  something to fix, from the user (an agent's
                                         report_problem, Settings)
  nixbook-improve drop-item ID           forget an inbox item
  nixbook-improve collect                file the shell's QML errors and the desktop tools'
                                         crashes since the last time (no model)
  nixbook-improve run [--item ID] [--auto] [--no-push]
                                         fix the ripest item (or ID): the session, the
                                         checks, the commit, the PR, then CI and the
                                         user's answer; --auto: the day's limit applies;
                                         --no-push: stop at the local commit
  nixbook-improve merge|drop|look PR     what the notification's buttons do
  nixbook-improve token set|forget|status
                                         its GitHub token (set: on stdin, checked on the
                                         repository, kept in the keyring): the only
                                         credential it uses, never the user's gh or ssh
  nixbook-improve health REV             the shell running a deployed fix (REV: the
                                         deployed revision): a revert offered if it broke
  nixbook-improve guard BASE [HEAD] [--max-files N] [--max-lines N]
                                         CI's agent-guard: an agent/ branch's commits are
                                         fixes (paths, size, messages)

Only where Nix made it available (programs.nixbook-shell.selfImprove.enable:
"improve" in desktop-mcp.json); guard and status run anywhere.
Every command prints JSON. State: $XDG_STATE_HOME/nixbook-shell/improve/,
the clone and logs: $XDG_DATA_HOME/nixbook-shell/improve/.`

func main() {
	out, err := dispatch(os.Args[1:])
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
	case "note":
		where, err := flag(&args, "--where")
		if err != nil {
			return nil, err
		}
		text := strings.TrimSpace(strings.Join(args, " "))
		if text == "" {
			return nil, errorf("say what to fix")
		}
		var it Item
		_, err = editInbox(func(in *Inbox) error {
			// The same words again count up instead of adding an item.
			key := "user:" + strings.ToLower(strings.Join(strings.Fields(text), " "))
			it = *in.add("user", clip(key, 200), text, clip(where, 200), 1, nowMs())
			return nil
		})
		return it, err
	case "drop-item":
		if len(args) != 1 {
			return nil, errorf("drop-item ID")
		}
		_, err := editInbox(func(in *Inbox) error {
			it := in.find(args[0])
			if it == nil {
				return errorf("no item %s", args[0])
			}
			it.Status = "dropped"
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
	return map[string]any{
		"available": available(), "token": available() && token() != "",
		"enable": cfg.Enable, "repo": ghRepo(cfg.Repo), "claude": cfg.claude != "",
		"today": runsToday(rs), "perDay": cfg.PerDay, "inbox": in.Items, "runs": rs,
	}, nil
}

// guardCmd checks BASE..HEAD of the repository in the working directory as
// run() checks a change before pushing it.
func guardCmd(args []string) (any, error) {
	files, err := flag(&args, "--max-files")
	if err != nil {
		return nil, err
	}
	lines, err := flag(&args, "--max-lines")
	if err != nil {
		return nil, err
	}
	d := defaults()
	lim := Limits{d.MaxFiles, d.MaxLines}
	if files != "" {
		lim.Files = atoi(files)
	}
	if lines != "" {
		lim.Lines = atoi(lines)
	}
	if len(args) < 1 || len(args) > 2 {
		return nil, errorf("guard BASE [HEAD]")
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
	why := checkDiff(parseDiff(num, names), lim)
	log, err := git(".", "log", "--format=%B%x00", base+".."+head)
	if err != nil {
		return nil, err
	}
	for _, msg := range strings.Split(log, "\x00") {
		if msg = strings.TrimSpace(msg); msg == "" {
			continue
		}
		var bad []string
		if strings.HasPrefix(msg, "Revert \"fix(") || strings.HasPrefix(msg, "Revert \"polish(") {
			// A revert this program made: its trailer only.
			if !trailerRe.MatchString(msg) {
				bad = []string{"no Agent-Fix: trailer"}
			}
		} else {
			bad = checkMessage(msg)
		}
		for _, b := range bad {
			why = append(why, fmt.Sprintf("commit %q: %s", firstLine(msg), b))
		}
	}
	if len(why) > 0 {
		emit(map[string]any{"ok": false, "why": why})
		os.Exit(1)
	}
	return map[string]any{"ok": true}, nil
}
