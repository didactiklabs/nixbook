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
costs more than none. If it can't be fixed here at all (it needs a place
off limits, credentials, hardware, a change outside nixbook), answer "cant"
and say what you looked at, why it can't be done here and what would make
it doable: it is dropped and the user told, never tried again unasked.
With skip, set harmless when it can be left as it is for good: nothing in
this repository can fix it and it does no harm (noise in a log, another
app's or the kernel's message, a warning nixbook can't silence). It is then
dropped and never tried again. Leave harmless out when the user notices it
or it may break something, or when a fix may be possible with more to go on.

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
- outcome: fixed, skip, too_big or cant;
- type: fix or polish;
- scope: what it is in, as in the git log (nixbook-shell, niri, docs…);
- title: lowercase, a sentence saying what is now right, like the git log
  ("the clock widget keeps its seconds after a theme switch"), no final
  period; with "fix(scope): " before it the line is 72 characters at most,
  so 50 for the title with the nixbook-shell scope;
- body: the changelog entry, in plain sentences, wrapped at 72 columns: what
  was wrong (what the user saw), the cause, what you changed and where, and
  how to see it is fixed. 40 to 150 words;
- reason: for skip, too_big and cant, why (for cant: what you looked at,
  why it can't be done here, what would make it doable);
- harmless: for skip, true when it can be ignored for good (see above).`

// featureRules: a feature's session. Bigger, new files allowed, never
// merged on its own; the same places off limits.
const featureRules = `You build a feature into nixbook, a NixOS configuration with its own
desktop shell (nixbook-shell, Quickshell/QML). The repository is your
working directory.

The user asked for this feature (or a fix turned out to need one). Build it
whole but small: the least code that does what was asked, in the places
such code already lives, reusing the services, widgets and settings that
exist. No refactor of what is around it, no dependency or pin bump, no
rename across files. At most %d files and %d changed lines; new files are
fine, deleting one isn't.
If it needs more than that, or a design choice only the user can make,
answer outcome "too_big" and say what it would take and what to decide. If
it can't be done here at all (it needs a place off limits, credentials,
hardware, a change outside nixbook), answer "cant". Either way say what you
looked at, why it can't be done and what would make it doable: it is
dropped and the user told, never tried again unasked. If it exists already
or the request is too vague to build, answer "skip" and say why (for one
that exists: how to use it).

These are off limits (a change to them is refused): .github/, tests/,
nixbook-shell/tests/, nixbook-shell/improve/, SelfImprove.qml, the agent
desktop's sandbox (agent-desktop.sh, wayland-security-context.py),
nixosModules/, installer/, lib/, profiles/, npins/, hive.nix, base.nix,
AGENTS.md, CLAUDE.md, secrets. Never widen what agents may do (their
tools, permissions, sandbox, switches) unless that is exactly what was
asked.

You can't run anything. Afterwards your change is built and checked: the
shell is started headless and must not print new QML warnings, and the
tests of what you touched run. So read the code around your change (its
imports, the properties it uses) and keep QML and Nix syntax exact.

Match the code around you: its naming, idioms and comment density. AGENTS.md
holds the conventions (it is long: Grep it for what you touch). A new
setting goes in the shell's Config.qml and builtin-defaults.json with a
control on its Settings page; a new shortcut in KEYBINDS.md; what users see
in its docs page (docs/nixbook-shell/) and in the assistant's how-to
answers (nixbook-shell/hm-module.nix, four languages), all in the same
change.

The repository is public. Your title and body become a commit message and
a pull request: never put the user's data in them (names, file paths in
their home, window titles, message or notification contents).

Answer with:
- outcome: built, skip, too_big or cant;
- scope: what it is in, as in the git log (nixbook-shell, niri, docs…);
- title: lowercase, a sentence saying what one can now do, like the git
  log ("the clock widget can show the week number"), no final period;
  with "feat(scope): " before it the line is 72 characters at most, so 51
  for the title with the nixbook-shell scope;
- body: the changelog entry, in plain sentences, wrapped at 72 columns:
  what it does, how to use it (where the setting, button or shortcut is),
  how it is made and where. 40 to 200 words;
- reason: for skip, too_big and cant, why.`

var featureSchema = `{"type":"object","properties":{
"outcome":{"type":"string","enum":["built","skip","too_big","cant"]},
"scope":{"type":"string"},
"title":{"type":"string"},
"body":{"type":"string"},
"reason":{"type":"string"}},
"required":["outcome"]}`

var answerSchema = `{"type":"object","properties":{
"outcome":{"type":"string","enum":["fixed","skip","too_big","cant"]},
"type":{"type":"string","enum":["fix","polish"]},
"scope":{"type":"string"},
"title":{"type":"string"},
"body":{"type":"string"},
"reason":{"type":"string"},
"harmless":{"type":"boolean"}},
"required":["outcome"]}`

type Answer struct {
	Outcome string `json:"outcome"`
	Type    string `json:"type"`
	Scope   string `json:"scope"`
	Title   string `json:"title"`
	Body    string `json:"body"`
	Reason  string `json:"reason"`
	// A skip that can be left for good: dropped, never tried again.
	Harmless bool `json:"harmless,omitempty"`
}

// made: the change is in the files (a fix fixed, a feature built).
func (a Answer) made() bool { return a.Outcome == "fixed" || a.Outcome == "built" }

type session struct {
	answer  Answer
	id      string
	cost    float64
	err     string
	denials int
}

// maskPrivate is the shell's privacy mask (Settings > Desktop agents >
// Private details) on what goes to Claude: logs and the user's reports may
// name people. `privacy mask` gives the text back as it is while the mask
// is off. Nothing is sent when it can't run. The answer keeps the
// placeholders: it goes to a public pull request.
func maskPrivate(text string) (string, error) {
	out, err := cmd("", time.Minute, text, "nixbook-desktop-mcp", "privacy", "mask")
	if err != nil || (out == "" && text != "") {
		return "", errorf("the private details couldn't be hidden, nothing sent: %v", err)
	}
	return out, nil
}

// ask runs the session, a fix's or a feature's (resume: the earlier one,
// told what went wrong).
func ask(cfg Config, dir, prompt, resume string, feature bool) (session, error) {
	if cfg.claude == "" {
		return session{}, errorf("no Claude Code (claude) found")
	}
	prompt, err := maskPrivate(prompt)
	if err != nil {
		return session{}, err
	}
	lim := cfg.limits(feature)
	rules, schema, turns, budget, limit := agentRules, answerSchema, "60", cfg.BudgetUsd, 40*time.Minute
	if feature {
		rules, schema, turns, budget, limit = featureRules, featureSchema, "150", cfg.Features.BudgetUsd, 90*time.Minute
	}
	args := []string{
		"-p", "--restricted", "--safe-mode", "--strict-mcp-config", "--output-format", "stream-json", "--verbose",
		"--tools", "Read,Edit,Write,Glob,Grep", "--permission-mode", "acceptEdits",
		"--model", cfg.Model, "--max-turns", turns, "--max-budget-usd", fmt.Sprintf("%.2f", budget),
		"--append-system-prompt", fmt.Sprintf(rules, lim.Files, lim.Lines),
		"--json-schema", schema,
	}
	if resume != "" {
		args = append(args, "--resume", resume)
	}
	claude := claudeCommand(cfg.claude, args)
	// Streamed: each tool call shows live (doing), the result comes last.
	out, err := stream(dir, limit, prompt, func(line string) {
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
	}, claude[0], claude[1:]...)
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
		return s, errorf("the session gave no answer (%s)", s.err)
	}
	if feature {
		s.answer.Type, s.answer.Harmless = "feat", false
	}
	return s, nil
}

// claudeCommand is Claude Code started through nixbook-model-provider,
// which points it at the model provider chosen in the shell's settings
// (Anthropic: the user's own login, unchanged); Claude Code as it is
// without the launcher.
func claudeCommand(claude string, args []string) []string {
	if provider, err := exec.LookPath("nixbook-model-provider"); err == nil {
		return append([]string{provider, "run", claude}, args...)
	}
	return append([]string{claude}, args...)
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
	case "regression":
		b.WriteString("A change merged lately broke this. It is not reverted: fix it forward, keeping what the change was for:\n\n")
	case "info":
		b.WriteString("This was seen on the computer. It isn't obviously nixbook's: if no change to this repository " +
			"can fix it (an upstream app's bug, hardware, the kernel), answer skip and say so, harmless if it does no harm.\n\n")
	case "feature":
		if it.From != "" {
			b.WriteString("This was filed as something to fix, and found too big for a fix (what the fixer found is at its end). Build it as a feature:\n\n")
		} else {
			b.WriteString("The user asked for this feature in nixbook (through their desktop agent or Settings):\n\n")
		}
	}
	b.WriteString("    " + strings.ReplaceAll(it.Text, "\n", "\n    ") + "\n")
	if it.Where != "" {
		fmt.Fprintf(&b, "\nWhere: %s\n", it.Where)
	}
	b.WriteString(context)
	if it.Note != "" {
		fmt.Fprintf(&b, "\nLast time: %s\n", it.Note)
	}
	if it.feature() {
		b.WriteString("\nBuild it, or say why not (skip, too_big, cant).")
	} else {
		b.WriteString("\nFind the cause and fix it, or say why not (skip, too_big, cant).")
	}
	return b.String()
}
