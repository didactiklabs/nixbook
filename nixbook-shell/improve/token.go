package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// Its GitHub token: the only credential it uses. Set in Settings (`token
// set`, on stdin), kept in the keyring (secret-tool, service
// nixbook-improve). gh gets it with an empty config dir and git over https
// with it alone: never the user's own gh login or ssh key. The fixing
// session never sees it. A fine-grained token for this repository only,
// Contents and Pull requests read and write, is all it needs.

var secretAttrs = []string{"service", "nixbook-improve", "account", "github"}

// token: the saved token, "" when none (NIXBOOK_IMPROVE_TOKEN in tests).
func token() string {
	if t := os.Getenv("NIXBOOK_IMPROVE_TOKEN"); t != "" {
		return t
	}
	out, err := cmd("", 20*time.Second, "", "secret-tool", append([]string{"lookup"}, secretAttrs...)...)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(out)
}

var errNoToken = errorf("no GitHub token: set one in Settings > Desktop agents > Fixes it makes itself")

// ghEnv: what gh and git run with, the token and nothing of the user's.
func ghEnv(tok string) []string {
	empty := filepath.Join(stateDir(), "gh")
	os.MkdirAll(empty, 0o700)
	return []string{
		"GH_TOKEN=" + tok, "GITHUB_TOKEN=", "GH_ENTERPRISE_TOKEN=", "GH_CONFIG_DIR=" + empty,
		"GH_HOST=github.com", "NIXBOOK_IMPROVE_GIT_TOKEN=" + tok,
	}
}

// gitAuth: git's options for the network: the token as the only
// credential (from the environment, never on the command line).
var gitAuth = []string{
	"-c", "credential.helper=", "-c",
	"credential.helper=!f() { echo username=x-access-token; echo \"password=$NIXBOOK_IMPROVE_GIT_TOKEN\"; }; f",
	"-c", "core.sshCommand=false",
}

// httpsURL: the repository's https address: an ssh one would use the
// user's key.
func httpsURL(repo string) string { return "https://github.com/" + repo + ".git" }

// probe: what the token can't do of what a fix needs ("" when it can),
// tried without changing anything: a pull request from a branch that
// doesn't exist (refused as invalid when allowed, as not accessible when
// not), and a dry-run push (authenticated, nothing sent).
func probe(tok, repo string) string {
	var missing []string
	out, err := cmdEnv("", time.Minute, "", ghEnv(tok), "gh", "api", "-X", "POST", "repos/"+repo+"/pulls",
		"-f", "title=nixbook-improve permission check", "-f", "head=nixbook-improve-no-such-branch", "-f", "base=main")
	if err == nil {
		// Can't happen (no such branch): never leave a PR behind.
		var pr struct{ Number int }
		if json.Unmarshal([]byte(out), &pr) == nil && pr.Number > 0 {
			cmdEnv("", time.Minute, "", ghEnv(tok), "gh", "pr", "close", itoa(pr.Number), "--repo", repo)
		}
	} else if !strings.Contains(out+err.Error(), "HTTP 422") {
		missing = append(missing, "Pull requests: Read and write")
	}
	tmp, err := os.MkdirTemp("", "nixbook-improve-probe")
	if err == nil {
		defer os.RemoveAll(tmp)
		// A throwaway repository with none of the user's git config (their
		// commit signing would fail the probe's commit, not the token).
		local := func(args ...string) (string, error) {
			return cmdEnv(tmp, time.Minute, "", gitIsolated, "git", args...)
		}
		local("init", "--quiet")
		if _, err := local("-c", "user.name=probe", "-c", "user.email=probe@localhost",
			"commit", "--quiet", "--allow-empty", "-m", "probe"); err != nil {
			return "the permission check itself failed: " + err.Error()
		}
		if _, err := cmdEnv(tmp, time.Minute, "", append(ghEnv(tok), gitIsolated...), "git", append(append([]string{}, gitAuth...),
			"push", "--dry-run", httpsURL(repo), "HEAD:refs/heads/nixbook-improve-permission-check")...); err != nil {
			switch msg := err.Error(); {
			case strings.Contains(msg, "Invalid username or token"):
				return "GitHub doesn't accept this token for git (" + gitReason(msg) + "): is it the token you just created, " +
					"not expired, and approved for " + strings.Split(repo, "/")[0] + " if the organization requires it?"
			case strings.Contains(msg, "403") || strings.Contains(msg, "denied") || strings.Contains(msg, "not granted"):
				missing = append([]string{"Contents: Read and write (git: " + gitReason(msg) + ")"}, missing...)
			default:
				return "the push check failed: " + gitReason(msg)
			}
		}
	}
	if len(missing) == 0 {
		return ""
	}
	return "the token can read " + repo + " but lacks " + strings.Join(missing, " and ") +
		" (GitHub > Settings > Developer settings > Fine-grained tokens > the token > Permissions)"
}

// gitReason: the remote's own words in a git error, short.
func gitReason(msg string) string {
	var lines []string
	for _, l := range strings.Split(msg, "\n") {
		l = strings.TrimSpace(l)
		if strings.HasPrefix(l, "remote:") || strings.HasPrefix(l, "fatal:") || strings.HasPrefix(l, "error:") {
			lines = append(lines, l)
		}
	}
	if len(lines) == 0 {
		return clip(msg, 200)
	}
	return clip(strings.Join(lines, " "), 300)
}

func tokenCmd(args []string) (any, error) {
	if len(args) != 1 {
		return nil, errorf("token set|forget|status")
	}
	switch args[0] {
	case "status":
		return map[string]any{"saved": token() != ""}, nil
	case "forget":
		_, err := cmd("", 20*time.Second, "", "secret-tool", append([]string{"clear"}, secretAttrs...)...)
		return map[string]any{"saved": false}, err
	case "set":
		b, err := readAll(os.Stdin)
		if err != nil {
			return nil, err
		}
		tok := strings.TrimSpace(string(b))
		if tok == "" {
			return nil, errorf("paste the token on stdin")
		}
		cfg, err := loadConfig()
		if err != nil {
			return nil, err
		}
		repo := ghRepo(cfg.Repo)
		if repo == "" {
			return nil, errorf("no GitHub repository: set updates.repoUrl (Settings > Services) or ai.improve.repo")
		}
		// It must reach the repository before it is kept.
		var r struct {
			FullName    string          `json:"full_name"`
			Permissions map[string]bool `json:"permissions"`
		}
		if err := ghJSONWith(tok, &r, "api", "repos/"+repo); err != nil {
			return nil, errorf("the token can't read %s: %v", repo, err)
		}
		if why := probe(tok, repo); why != "" {
			return nil, errorf("%s", why)
		}
		if _, err := cmd("", 20*time.Second, tok, "secret-tool", append([]string{
			"store",
			"--label=nixbook-improve GitHub token",
		}, secretAttrs...)...); err != nil {
			return nil, err
		}
		out := map[string]any{"saved": true, "repo": r.FullName}
		if strings.HasPrefix(tok, "ghp_") || strings.HasPrefix(tok, "gho_") {
			out["warning"] = "a classic token reaches every repository you can: a fine-grained one for this repository only is safer"
		}
		if r.Permissions != nil && r.Permissions["admin"] {
			out["warning"] = "this token is an admin of the repository: one with Contents and Pull requests only is safer"
		}
		return out, nil
	}
	return nil, errorf("token set|forget|status")
}
