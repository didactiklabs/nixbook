package main

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

// cmd runs a command in dir with a time limit: its output, and an error
// carrying the end of what it printed.
func cmd(dir string, limit time.Duration, stdin string, name string, args ...string) (string, error) {
	return cmdEnv(dir, limit, stdin, nil, name, args...)
}

// secretEnv: tokens of the user's environment, never passed on (the
// fixing session included).
var secretEnv = []string{"GH_TOKEN=", "GITHUB_TOKEN=", "GH_ENTERPRISE_TOKEN=", "NIXBOOK_IMPROVE_GIT_TOKEN="}

func cmdEnv(dir string, limit time.Duration, stdin string, env []string, name string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), limit)
	defer cancel()
	c := exec.CommandContext(ctx, name, args...)
	c.Dir = dir
	// Never a prompt (credentials, ssh host keys): it runs unattended.
	c.Env = append(append(append(os.Environ(), secretEnv...), "GIT_TERMINAL_PROMPT=0", "GH_PROMPT_DISABLED=1",
		"GIT_SSH_COMMAND=ssh -o BatchMode=yes"), env...)
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

// gitNet: git reaching GitHub, with the token only.
func gitNet(dir string, args ...string) (string, error) {
	tok := token()
	if tok == "" {
		return "", errNoToken
	}
	out, err := cmdEnv(dir, 30*time.Minute, "", ghEnv(tok), "git", append(append([]string{}, gitAuth...), args...)...)
	return strings.TrimSpace(out), err
}

// gh runs gh with the token only (none: refused).
func gh(args ...string) (string, error) {
	return ghIn(2*time.Minute, "", args...)
}

func ghIn(limit time.Duration, stdin string, args ...string) (string, error) {
	tok := token()
	if tok == "" {
		return "", errNoToken
	}
	out, err := cmdEnv("", limit, stdin, ghEnv(tok), "gh", args...)
	return strings.TrimSpace(out), err
}

func ghJSON(v any, args ...string) error {
	out, err := gh(args...)
	if err != nil {
		return err
	}
	return json.Unmarshal([]byte(out), v)
}

func ghJSONWith(tok string, v any, args ...string) error {
	out, err := cmdEnv("", 2*time.Minute, "", ghEnv(tok), "gh", args...)
	if err != nil {
		return err
	}
	return json.Unmarshal([]byte(out), v)
}

func readAll(r io.Reader) ([]byte, error) { return io.ReadAll(io.LimitReader(r, 1<<16)) }

func tail(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return "…" + s[len(s)-n:]
}

func itoa(n int) string { return strconv.Itoa(n) }

func atoi(s string) int {
	n, _ := strconv.Atoi(strings.TrimSpace(s))
	return n
}
