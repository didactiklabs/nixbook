package main

import (
	"encoding/json"
	"fmt"
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
  ("the clock widget keeps its seconds after a theme switch"), 60
  characters at most, no final period;
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
		"-p", "--restricted", "--safe-mode", "--strict-mcp-config", "--output-format", "json",
		"--tools", "Read,Edit,Write,Glob,Grep", "--permission-mode", "acceptEdits",
		"--model", cfg.Model, "--max-turns", "60", "--max-budget-usd", fmt.Sprintf("%.2f", cfg.BudgetUsd),
		"--append-system-prompt", fmt.Sprintf(agentRules, fixLimits.Files, fixLimits.Lines),
		"--json-schema", answerSchema,
	}
	if resume != "" {
		args = append(args, "--resume", resume)
	}
	out, err := cmd(dir, 40*time.Minute, prompt, cfg.claude, args...)
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
func firstPrompt(it Item) string {
	var b strings.Builder
	switch it.Kind {
	case "user":
		b.WriteString("The user reported this about nixbook (through their desktop agent or Settings):\n\n")
	case "qml":
		fmt.Fprintf(&b, "The running shell printed this warning %d times lately (its journal):\n\n", it.Count)
	case "crash":
		fmt.Fprintf(&b, "A desktop tool of nixbook-desktop-mcp crashed %d times lately (an exception, not a refusal):\n\n", it.Count)
	}
	b.WriteString("    " + strings.ReplaceAll(it.Text, "\n", "\n    ") + "\n")
	if it.Where != "" {
		fmt.Fprintf(&b, "\nWhere: %s\n", it.Where)
	}
	if it.Note != "" {
		fmt.Fprintf(&b, "\nLast time: %s\n", it.Note)
	}
	b.WriteString("\nFind the cause and fix it, or say why not (skip, too_big).")
	return b.String()
}
