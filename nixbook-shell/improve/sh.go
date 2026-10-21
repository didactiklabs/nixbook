package main

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

// cmd runs a command in dir with a time limit: its output, and an error
// carrying the end of what it printed.
func cmd(dir string, limit time.Duration, stdin string, name string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), limit)
	defer cancel()
	c := exec.CommandContext(ctx, name, args...)
	c.Dir = dir
	// Never a prompt (credentials, ssh host keys): it runs unattended.
	c.Env = append(os.Environ(), "GIT_TERMINAL_PROMPT=0", "GH_PROMPT_DISABLED=1", "GIT_SSH_COMMAND=ssh -o BatchMode=yes")
	if stdin != "" {
		c.Stdin = strings.NewReader(stdin)
	}
	var out, errb bytes.Buffer
	c.Stdout, c.Stderr = &out, &errb
	err := c.Run()
	if ctx.Err() == context.DeadlineExceeded {
		return out.String(), errorf("%s: timed out after %s", name, limit)
	}
	if err != nil {
		msg := strings.TrimSpace(errb.String())
		if msg == "" {
			msg = strings.TrimSpace(out.String())
		}
		return out.String(), errorf("%s %s: %v: %s", name, strings.Join(args[:min(len(args), 2)], " "), err, tail(msg, 1500))
	}
	return out.String(), nil
}

func git(dir string, args ...string) (string, error) {
	out, err := cmd(dir, 10*time.Minute, "", "git", args...)
	return strings.TrimSpace(out), err
}

// ghCred: pushes to an https remote with gh's login (ssh ones use the
// user's ssh agent).
var ghCred = []string{"-c", "credential.helper=", "-c", "credential.helper=!gh auth git-credential"}

func gh(args ...string) (string, error) {
	out, err := cmd("", 2*time.Minute, "", "gh", args...)
	return strings.TrimSpace(out), err
}

func ghJSON(v any, args ...string) error {
	out, err := gh(args...)
	if err != nil {
		return err
	}
	return json.Unmarshal([]byte(out), v)
}

func tail(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return "…" + s[len(s)-n:]
}

func atoi(s string) int {
	n, _ := strconv.Atoi(strings.TrimSpace(s))
	return n
}
