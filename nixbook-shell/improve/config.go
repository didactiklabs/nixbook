package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// Config is ai.improve of the shell's config.json (Settings > Desktop
// agents > "Fixes it makes itself"), with what it borrows elsewhere.
type Config struct {
	Enable bool `json:"enable"`
	// Model of the fixing session (Claude Code's alias or full name).
	Model string `json:"model"`
	// Runs started on its own per day ("Fix now" isn't counted); 0: no
	// limit but BudgetUsd per run.
	PerDay int `json:"perDay"`
	// The size a change may have: beyond, it is a feature or a refactor,
	// not a fix, and is refused.
	MaxFiles int `json:"maxFiles"`
	MaxLines int `json:"maxLines"`
	// The most a fixing session may spend (Claude Code's --max-budget-usd).
	BudgetUsd float64 `json:"budgetUsd"`
	// Merged without asking once its checks pass, when every changed file
	// matches AutoMergePaths and none is sensitive.
	AutoMerge      bool     `json:"autoMerge"`
	AutoMergePaths []string `json:"autoMergePaths"`
	// Every fix merged once CI passes, not only docs (sensitive files
	// still wait for the user).
	AutoMergeFixes bool `json:"autoMergeFixes"`
	// CI jobs whose failure isn't the code's (uploading to the binary cache).
	CIIgnoreJobs []string `json:"ciIgnoreJobs"`
	// The repository (empty: updates.repoUrl, the one the update check reads).
	Repo string `json:"repo"`
	// Features it builds (ai.improve.features), apart from the fixes: what
	// the user asks for and fixes found too big. Same model, token and
	// repository; never merged on its own.
	Features Features `json:"features"`

	claude string
	// policies.ai of the shell: 0 no AI, 1 yes, 2 local models only.
	aiPolicy int
}

type Features struct {
	Enable bool `json:"enable"`
	// Features started on its own per day ("Build now" isn't counted); 0:
	// no limit.
	PerDay    int     `json:"perDay"`
	MaxFiles  int     `json:"maxFiles"`
	MaxLines  int     `json:"maxLines"`
	BudgetUsd float64 `json:"budgetUsd"`
}

func defaults() Config {
	return Config{
		Model: "sonnet", PerDay: 2, MaxFiles: 5, MaxLines: 150, BudgetUsd: 3,
		AutoMergePaths: []string{"docs/**", "**/*.md"}, CIIgnoreJobs: []string{"push-cache"},
		Features: Features{PerDay: 1, MaxFiles: 15, MaxLines: 600, BudgetUsd: 8},
	}
}

// limits: the size a change may have, a fix's or a feature's.
func (c Config) limits(feature bool) Limits {
	if feature {
		return Limits{Files: c.Features.MaxFiles, Lines: c.Features.MaxLines, NewFiles: true}
	}
	return Limits{Files: c.MaxFiles, Lines: c.MaxLines}
}

// perDay: the day's limit of runs of this kind started on its own (0: none).
func (c Config) perDay(feature bool) int {
	if feature {
		return c.Features.PerDay
	}
	return c.PerDay
}

// room: another run of this kind may start on its own today.
func (c Config) room(rs []Run, feature bool) bool {
	n := c.perDay(feature)
	return n == 0 || runsToday(rs, feature) < n
}

// on: runs of this kind are allowed.
func (c Config) on(feature bool) bool {
	if feature {
		return c.Features.Enable
	}
	return c.Enable
}

func loadConfig() (Config, error) {
	var raw struct {
		Ai struct {
			Improve    *Config `json:"improve"`
			ClaudeCode struct {
				Command string `json:"command"`
			} `json:"claudeCode"`
		} `json:"ai"`
		Updates struct {
			RepoURL string `json:"repoUrl"`
		} `json:"updates"`
		Policies struct {
			Ai *int `json:"ai"`
		} `json:"policies"`
	}
	cfg := defaults()
	raw.Ai.Improve = &cfg
	if err := readJSON(configPath(), &raw); err != nil {
		return cfg, errorf("the shell's config: %v", err)
	}
	d := defaults()
	if cfg.Model == "" {
		cfg.Model = d.Model
	}
	if cfg.PerDay < 0 {
		cfg.PerDay = 0
	}
	if cfg.MaxFiles <= 0 {
		cfg.MaxFiles = d.MaxFiles
	}
	if cfg.MaxLines <= 0 {
		cfg.MaxLines = d.MaxLines
	}
	if cfg.BudgetUsd <= 0 {
		cfg.BudgetUsd = d.BudgetUsd
	}
	if cfg.Features.PerDay < 0 {
		cfg.Features.PerDay = 0
	}
	if cfg.Features.MaxFiles <= 0 {
		cfg.Features.MaxFiles = d.Features.MaxFiles
	}
	if cfg.Features.MaxLines <= 0 {
		cfg.Features.MaxLines = d.Features.MaxLines
	}
	if cfg.Features.BudgetUsd <= 0 {
		cfg.Features.BudgetUsd = d.Features.BudgetUsd
	}
	if cfg.Repo == "" {
		cfg.Repo = raw.Updates.RepoURL
	}
	cfg.claude = findClaude(raw.Ai.ClaudeCode.Command)
	cfg.aiPolicy = 1
	if raw.Policies.Ai != nil {
		cfg.aiPolicy = *raw.Policies.Ai
	}
	return cfg, nil
}

// available: this machine has the feature (programs.nixbook-shell.selfImprove.enable,
// written by Nix into desktop-mcp.json as "improve"). Without it nothing
// runs, whatever config.json says.
func available() bool {
	path := os.Getenv("NIXBOOK_DESKTOP_MCP_CONFIG")
	if path == "" {
		path = filepath.Join(xdg("XDG_CONFIG_HOME", ".config"), "nixbook-shell", "desktop-mcp.json")
	}
	var c struct {
		Improve bool `json:"improve"`
	}
	return readJSON(path, &c) == nil && c.Improve
}

var errUnavailable = errorf("not available on this machine (programs.nixbook-shell.selfImprove.enable)")

// findClaude looks where Ai.qml and desktop-mcp.py look.
func findClaude(hint string) string {
	home, _ := os.UserHomeDir()
	onPath, _ := exec.LookPath("claude")
	for _, c := range []string{
		hint, os.Getenv("NIXBOOK_IMPROVE_CLAUDE"), onPath,
		filepath.Join(home, ".local/bin/claude"), filepath.Join(home, ".nix-profile/bin/claude"),
		"/etc/profiles/per-user/" + os.Getenv("USER") + "/bin/claude", "/run/current-system/sw/bin/claude",
	} {
		if c == "" {
			continue
		}
		if st, err := os.Stat(c); err == nil && !st.IsDir() && st.Mode()&0o111 != 0 {
			return c
		}
	}
	return ""
}

// ghRepo is OWNER/NAME of a GitHub URL (https or ssh), "" otherwise.
func ghRepo(url string) string {
	u := strings.TrimSuffix(strings.TrimSpace(url), "/")
	u = strings.TrimSuffix(u, ".git")
	for _, p := range []string{"https://github.com/", "http://github.com/", "ssh://git@github.com/", "git@github.com:"} {
		if strings.HasPrefix(strings.ToLower(u), p) {
			rest := u[len(p):]
			if parts := strings.Split(rest, "/"); len(parts) == 2 && parts[0] != "" && parts[1] != "" {
				return rest
			}
		}
	}
	return ""
}
