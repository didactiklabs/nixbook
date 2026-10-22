package main

import (
	"fmt"
	"regexp"
	"strings"
)

// What a fix may touch. One list for the run (before anything is pushed)
// and for CI's agent-guard job (checks.yaml), which runs `nixbook-improve
// guard` on every agent/ branch: an agent that got around the first meets
// the second, and can't change either (this directory is forbidden).

// forbidden: never changed by a fix. What keeps agents in check (their
// sandbox, this fixer, CI), what other agents read as instructions, what
// reaches every machine as root, secrets and pins.
var forbidden = []string{
	".github/**", ".claude/**", ".envrc",
	"nixbook-shell/improve/**", "nixbook-shell/src/services/SelfImprove.qml",
	"nixbook-shell/scripts/agent-desktop.sh", "nixbook-shell/scripts/wayland-security-context.py",
	"nixbook-shell/niri-winit-agent-window.patch",
	"tests/**", "nixbook-shell/tests/**",
	"nixosModules/**", "installer/**", "lib/**", "profiles/**", "secrets/**",
	"npins/**", "nixbook-shell/npins/**", "**/*.age", "**/*.lock",
	"hive.nix", "base.nix", "default.nix", "devenv.nix", "devenv.yaml",
	"**/AGENTS.md", "**/CLAUDE.md",
}

// sensitive: a fix may change them, but the user always merges it: what
// agents may do (tools, permissions, the switches and their defaults) and
// the shell's packaging.
var sensitive = []string{
	"nixbook-shell/scripts/desktop-mcp.py",
	"nixbook-shell/src/services/Ai.qml", "nixbook-shell/src/services/AiChatSession.qml",
	"nixbook-shell/src/services/Initiative.qml", "nixbook-shell/src/services/Routines.qml",
	"nixbook-shell/src/modules/common/Config.qml", "nixbook-shell/builtin-defaults.json",
	"nixbook-shell/src/modules/ii/settings/pages/DesktopAgentsConfig.qml",
	"nixbook-shell/*.nix", "customPkgs/**", "homeManagerModules/**",
}

var globCache = map[string]*regexp.Regexp{}

// matchGlob: `**` any number of directories, `*` and `?` within one.
func matchGlob(glob, path string) bool {
	re, ok := globCache[glob]
	if !ok {
		var b strings.Builder
		b.WriteString("^")
		for i := 0; i < len(glob); i++ {
			switch c := glob[i]; {
			case strings.HasPrefix(glob[i:], "**/"):
				b.WriteString("(?:.*/)?")
				i += 2
			case strings.HasPrefix(glob[i:], "**"):
				b.WriteString(".*")
				i++
			case c == '*':
				b.WriteString("[^/]*")
			case c == '?':
				b.WriteString("[^/]")
			default:
				b.WriteString(regexp.QuoteMeta(string(c)))
			}
		}
		b.WriteString("$")
		re = regexp.MustCompile(b.String())
		globCache[glob] = re
	}
	return re.MatchString(path)
}

func matchAny(globs []string, path string) bool {
	for _, g := range globs {
		if matchGlob(g, path) {
			return true
		}
	}
	return false
}

// A Change is one file of a diff (git diff --numstat / --name-status).
type Change struct {
	Path    string `json:"path"`
	Status  string `json:"status"` // A, M, D, R
	Added   int    `json:"added"`
	Deleted int    `json:"deleted"`
	Binary  bool   `json:"binary,omitempty"`
}

type Limits struct {
	Files, Lines int
	// A feature may add files (a fix only Markdown ones).
	NewFiles bool
}

// checkDiff: why this change can't be a fix, or a feature with
// lim.NewFiles ("" when it can).
func checkDiff(changes []Change, lim Limits) []string {
	var why []string
	if len(changes) == 0 {
		return []string{"nothing changed"}
	}
	what := "a fix"
	if lim.NewFiles {
		what = "a feature"
	}
	if len(changes) > lim.Files {
		why = append(why, fmt.Sprintf("%d files changed, %s changes at most %d", len(changes), what, lim.Files))
	}
	lines := 0
	for _, c := range changes {
		lines += c.Added + c.Deleted
		switch {
		case matchAny(forbidden, c.Path):
			why = append(why, c.Path+" is off limits to agents")
		case c.Binary:
			why = append(why, c.Path+": a binary file")
		case c.Status == "D":
			why = append(why, c.Path+": deleting a file isn't "+what)
		case c.Status == "A" && !lim.NewFiles && !strings.HasSuffix(c.Path, ".md"):
			why = append(why, c.Path+": a new file isn't a fix")
		}
	}
	if lines > lim.Lines {
		why = append(why, fmt.Sprintf("%d lines changed, %s changes at most %d", lines, what, lim.Lines))
	}
	return why
}

// checkReverts: a revert this program made only takes a change back, so
// only its paths are checked (it deletes what a feature added, and may be
// as big).
func checkReverts(changes []Change) []string {
	var why []string
	for _, c := range changes {
		if matchAny(forbidden, c.Path) {
			why = append(why, c.Path+" is off limits to agents")
		}
	}
	return why
}

func anySensitive(changes []Change) bool {
	for _, c := range changes {
		if matchAny(sensitive, c.Path) {
			return true
		}
	}
	return false
}

// autoMergeWhy: why this change may merge without the user ("" when it
// may not): every fix (autoMergeFixes) or a docs-only one (autoMerge and
// autoMergePaths). Never a feature (the user looks at what it adds), nor
// one touching what agents may do (sensitive): the fixer would otherwise
// merge a loosening of its own limits unseen.
func autoMergeWhy(cfg Config, changes []Change, feature bool) string {
	switch {
	case feature || len(changes) == 0 || anySensitive(changes):
		return ""
	case cfg.AutoMergeFixes:
		return "every fix merges on its own"
	case cfg.AutoMerge && autoMergeable(changes, cfg.AutoMergePaths):
		return "it only touched " + strings.Join(cfg.AutoMergePaths, ", ")
	}
	return ""
}

// autoMergeable: every file is in the user's low-risk paths, none sensitive.
func autoMergeable(changes []Change, paths []string) bool {
	if len(changes) == 0 || anySensitive(changes) {
		return false
	}
	for _, c := range changes {
		if !matchAny(paths, c.Path) {
			return false
		}
	}
	return true
}

var (
	titleRe       = regexp.MustCompile(`^(fix|polish)\([a-z0-9][a-z0-9./-]*\): \S.{6,}$`)
	featTitleRe   = regexp.MustCompile(`^feat\([a-z0-9][a-z0-9./-]*\): \S.{6,}$`)
	trailerRe     = regexp.MustCompile(`(?m)^Agent-Fix: [0-9a-f]{8}$`)
	featTrailerRe = regexp.MustCompile(`(?m)^Agent-Feature: [0-9a-f]{8}$`)
	anyTrailerRe  = regexp.MustCompile(`(?m)^Agent-(Fix|Feature): [0-9a-f]{8}$`)
	revertTitleRe = regexp.MustCompile(`^Revert "(fix|polish|feat)\(`)
)

// checkMessage: a fix's commit says what it does, so the commits read as a
// changelog: "fix(scope): …" or "polish(scope): …", a body of whole
// sentences, and the inbox item it answers. A feature's (feature: an
// agent/feature- branch) is "feat(scope): …" with an Agent-Feature: trailer.
func checkMessage(msg string, feature bool) []string {
	var why []string
	title, body, _ := strings.Cut(strings.TrimSpace(msg), "\n")
	tre, tr, trailer := titleRe, trailerRe, "Agent-Fix:"
	if feature {
		tre, tr, trailer = featTitleRe, featTrailerRe, "Agent-Feature:"
	}
	if !tre.MatchString(title) {
		if feature {
			why = append(why, fmt.Sprintf("title %q isn't feat(scope): …", title))
		} else {
			why = append(why, fmt.Sprintf("title %q isn't fix(scope): … or polish(scope): …", title))
		}
	}
	if len([]rune(title)) > 72 {
		why = append(why, "title longer than 72 characters")
	}
	text := anyTrailerRe.ReplaceAllString(body, "")
	if len(strings.Fields(text)) < 20 {
		why = append(why, "the body doesn't say what changed and why (20 words at least)")
	}
	if !tr.MatchString(body) {
		why = append(why, "no "+trailer+" trailer")
	}
	return why
}
