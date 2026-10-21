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
		git(tmp, "init", "--quiet")
		git(tmp, "-c", "user.name=probe", "-c", "user.email=probe@localhost", "commit", "--quiet", "--allow-empty", "-m", "probe")
		if _, err := cmdEnv(tmp, time.Minute, "", ghEnv(tok), "git", append(append([]string{}, gitAuth...),
			"push", "--dry-run", httpsURL(repo), "HEAD:refs/heads/nixbook-improve-permission-check")...); err != nil {
			missing = append([]string{"Contents: Read and write"}, missing...)
		}
	}
	if len(missing) == 0 {
		return ""
	}
	return "the token can read " + repo + " but lacks " + strings.Join(missing, " and ") +
		" (GitHub > Settings > Developer settings > Fine-grained tokens > the token > Permissions)"
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
