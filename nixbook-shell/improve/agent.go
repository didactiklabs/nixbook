package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"
)

// The fixing session: Claude Code in --restricted mode in the clone. Its
// file tools stay inside the clone, it runs nothing (no Bash, no web), reads
// no settings, hooks or MCP servers. It only edits; this program checks,
// commits and pushes, so it never holds a credential.

const agentRules = `You fix nixbook, a NixOS configuration with its own desktop shell
(nixbook-shell, Quickshell/QML). The repository is your working directory.

You make FIXES and POLISH only:
- fix: a bug (an error the shell prints, a crash of a desktop tool, something
  that doesn't do what it says);
- polish: a small rough edge (wrong or unclear wording, a misaligned or
  clipped element, a missing translation, a wrong default, a typo).
Never a new feature, a new setting, a refactor, a dependency or pin bump, a
rename across files, or a rewrite. At most %d files and %d changed lines; no
new files (but Markdown), no deleted ones.
If the problem needs more than that, answer outcome "too_big" and say what a
real change would be. If it isn't a bug, is already fixed, or you can't find
its cause in the code, answer "skip" and say why. Don't guess: a wrong fix
costs more than none.

These are off limits (a change to them is refused): .github/, tests/,
nixbook-shell/tests/, nixbook-shell/improve/, SelfImprove.qml, the agent
desktop's sandbox (agent-desktop.sh, wayland-security-context.py),
nixosModules/, installer/, lib/, profiles/, npins/, hive.nix, base.nix,
AGENTS.md, CLAUDE.md, secrets.

You can't run anything. Afterwards your change is built and checked: the
shell is started headless and must not print new QML warnings, and the
tests of what you touched run. So read the code around your change (its
imports, the properties it uses) and keep QML and Nix syntax exact.

Match the code around you: its naming, idioms and comment density. AGENTS.md
holds the conventions (it is long: Grep it for what you touch). When a fix
changes what a user sees or does, also fix the matching docs page
(docs/nixbook-shell/) in the same change.

The repository is public. Your title and body become a commit message and
a pull request: never put the user's data in them (names, file paths in
their home, window titles, message or notification contents).

Answer with:
- outcome: fixed, skip or too_big;
- type: fix or polish;
- scope: what it is in, as in the git log (nixbook-shell, niri, docs…);
- title: lowercase, a sentence saying what is now right, like the git log
  ("the clock widget keeps its seconds after a theme switch"), no final
  period; with "fix(scope): " before it the line is 72 characters at most,
  so 50 for the title with the nixbook-shell scope;
- body: the changelog entry, in plain sentences, wrapped at 72 columns: what
  was wrong (what the user saw), the cause, what you changed and where, and
  how to see it is fixed. 40 to 150 words;
- reason: for skip and too_big, why.`

var answerSchema = `{"type":"object","properties":{
"outcome":{"type":"string","enum":["fixed","skip","too_big"]},
"type":{"type":"string","enum":["fix","polish"]},
"scope":{"type":"string"},
"title":{"type":"string"},
"body":{"type":"string"},
"reason":{"type":"string"}},
"required":["outcome"]}`

type Answer struct {
	Outcome string `json:"outcome"`
	Type    string `json:"type"`
	Scope   string `json:"scope"`
	Title   string `json:"title"`
	Body    string `json:"body"`
	Reason  string `json:"reason"`
}

type session struct {
	answer  Answer
	id      string
	cost    float64
	err     string
	denials int
}

// ask runs the session (resume: the earlier one, told what went wrong).
func ask(cfg Config, dir, prompt, resume string, fixLimits Limits) (session, error) {
	if cfg.claude == "" {
		return session{}, errorf("no Claude Code (claude) found")
	}
	args := []string{
		"-p", "--restricted", "--safe-mode", "--strict-mcp-config", "--output-format", "stream-json", "--verbose",
		"--tools", "Read,Edit,Write,Glob,Grep", "--permission-mode", "acceptEdits",
		"--model", cfg.Model, "--max-turns", "60", "--max-budget-usd", fmt.Sprintf("%.2f", cfg.BudgetUsd),
		"--append-system-prompt", fmt.Sprintf(agentRules, fixLimits.Files, fixLimits.Lines),
		"--json-schema", answerSchema,
	}
	if resume != "" {
		args = append(args, "--resume", resume)
	}
	// Streamed: each tool call shows live (doing), the result comes last.
	out, err := stream(dir, 40*time.Minute, prompt, func(line string) {
		var ev struct {
			Type    string `json:"type"`
			Message struct {
				Content []struct {
					Type  string         `json:"type"`
					Name  string         `json:"name"`
					Input map[string]any `json:"input"`
				} `json:"content"`
			} `json:"message"`
		}
		if json.Unmarshal([]byte(line), &ev) != nil || ev.Type != "assistant" {
			return
		}
		for _, c := range ev.Message.Content {
			if c.Type == "tool_use" {
				doing(describeTool(c.Name, c.Input, dir))
			}
		}
	}, cfg.claude, args...)
	var res struct {
		IsError    bool            `json:"is_error"`
		Subtype    string          `json:"subtype"`
		Result     string          `json:"result"`
		SessionID  string          `json:"session_id"`
		Cost       float64         `json:"total_cost_usd"`
		Structured json.RawMessage `json:"structured_output"`
		Denials    []any           `json:"permission_denials"`
	}
	if jerr := json.Unmarshal([]byte(lastJSONLine(out)), &res); jerr != nil {
		if err != nil {
			return session{}, err
		}
		return session{}, errorf("the fixing session's answer: %v", jerr)
	}
	s := session{id: res.SessionID, cost: res.Cost, denials: len(res.Denials)}
	if len(res.Structured) == 0 || json.Unmarshal(res.Structured, &s.answer) != nil || s.answer.Outcome == "" {
		s.err = clip(fmt.Sprintf("%s: %s", res.Subtype, res.Result), 400)
		return s, errorf("the fixing session gave no answer (%s)", s.err)
	}
	return s, nil
}

// stream runs a command, handing each line of its output to onLine as it
// comes; the output whole, and an error with its end.
func stream(dir string, limit time.Duration, stdin string, onLine func(string), name string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), limit)
	defer cancel()
	c := exec.CommandContext(ctx, name, args...)
	c.Dir = dir
	c.Env = append(append(os.Environ(), secretEnv...), "GIT_TERMINAL_PROMPT=0")
	c.Stdin = strings.NewReader(stdin)
	var errb bytes.Buffer
	c.Stderr = &errb
	pipe, err := c.StdoutPipe()
	if err != nil {
		return "", err
	}
	if err := c.Start(); err != nil {
		return "", err
	}
	var out strings.Builder
	sc := bufio.NewScanner(pipe)
	// A Write's whole file is on one line.
	sc.Buffer(make([]byte, 64*1024), 64<<20)
	for sc.Scan() {
		line := sc.Text()
		out.WriteString(line + "\n")
		onLine(line)
	}
	err = c.Wait()
	if ctx.Err() == context.DeadlineExceeded {
		return out.String(), errorf("%s: timed out after %s", name, limit)
	}
	if err != nil {
		return out.String(), errorf("%s: %v: %s", name, err, tail(strings.TrimSpace(errb.String()), 1500))
	}
	return out.String(), nil
}

func lastJSONLine(out string) string {
	lines := strings.Split(strings.TrimSpace(out), "\n")
	for i := len(lines) - 1; i >= 0; i-- {
		if strings.HasPrefix(strings.TrimSpace(lines[i]), "{") {
			return lines[i]
		}
	}
	return out
}

// firstPrompt: the item, as the session gets it.
// atRev: the lines around a QML warning in the revision that printed it
// (the clone has its history; main may have moved since), "" if unknown.
func atRev(repo string, it Item) string {
	if it.Kind != "qml" || it.Rev == "" || it.Line <= 0 {
		return ""
	}
	src, err := git(repo, "show", it.Rev+":"+it.Where)
	if err != nil {
		return ""
	}
	lines := strings.Split(src, "\n")
	from, to := max(it.Line-8, 1), min(it.Line+8, len(lines))
	if from > to {
		return ""
	}
	var b strings.Builder
	fmt.Fprintf(&b, "\nThe line numbers are from revision %s, which the shell printing it runs; main may have moved since. There, %s:\n", it.Rev[:min(len(it.Rev), 12)], it.Where)
	for i := from; i <= to; i++ {
		mark := "  "
		if i == it.Line {
			mark = "> "
		}
		fmt.Fprintf(&b, "%s%5d  %s\n", mark, i, lines[i-1])
	}
	b.WriteString("Find the same code on main and fix it there.\n")
	return b.String()
}

func firstPrompt(it Item, context string) string {
	var b strings.Builder
	switch it.Kind {
	case "user":
		b.WriteString("The user reported this about nixbook (through their desktop agent or Settings):\n\n")
	case "qml":
		fmt.Fprintf(&b, "The running shell printed this warning %d times lately (its journal):\n\n", it.Count)
	case "crash":
		fmt.Fprintf(&b, "A desktop tool of nixbook-desktop-mcp crashed %d times lately (an exception, not a refusal):\n\n", it.Count)
	case "service":
		b.WriteString("A systemd unit nixbook defines (or configures) is in the failed state on this computer:\n\n")
	case "log":
		fmt.Fprintf(&b, "A systemd unit nixbook defines logged this error %d times lately:\n\n", it.Count)
	case "deploy":
		b.WriteString("The last system update of this computer (osupdate: colmena with this repository) failed:\n\n")
	case "warning":
		fmt.Fprintf(&b, "The system update printed this Nix warning (%d updates):\n\n", it.Count)
	case "ci":
		b.WriteString("A CI workflow fails on main:\n\n")
	case "coredump":
		fmt.Fprintf(&b, "A program nixbook packages (customPkgs/ or nixbook-shell) crashed %d times lately:\n\n", it.Count)
	case "info":
		b.WriteString("This was seen on the computer. It isn't obviously nixbook's: if no change to this repository " +
			"can fix it (an upstream app's bug, hardware, the kernel), answer skip and say so.\n\n")
	}
	b.WriteString("    " + strings.ReplaceAll(it.Text, "\n", "\n    ") + "\n")
	if it.Where != "" {
		fmt.Fprintf(&b, "\nWhere: %s\n", it.Where)
	}
	b.WriteString(context)
	if it.Note != "" {
		fmt.Fprintf(&b, "\nLast time: %s\n", it.Note)
	}
	b.WriteString("\nFind the cause and fix it, or say why not (skip, too_big).")
	return b.String()
}
