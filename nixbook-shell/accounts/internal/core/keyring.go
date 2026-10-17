package core

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// Secrets live in the keyring through secret-tool (libsecret), under
// application=nixbook-accounts kind=<kind>; NIXBOOK_ACCOUNTS_SECRETS_DIR keeps
// them in files instead, for the tests only.

func secretsDir() string { return os.Getenv("NIXBOOK_ACCOUNTS_SECRETS_DIR") }

func secretTool(input string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "secret-tool", args...)
	if input != "" {
		cmd.Stdin = strings.NewReader(input)
	}
	var stderr strings.Builder
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	switch {
	case errors.Is(err, exec.ErrNotFound):
		return "", Errorf("secret-tool (libsecret) isn't installed")
	case ctx.Err() != nil:
		return "", Errorf("the keyring didn't answer: is it unlocked?")
	case err != nil:
		return "", &exitError{err: err, stderr: strings.TrimSpace(stderr.String())}
	}
	return string(out), nil
}

type exitError struct {
	err    error
	stderr string
}

func (e *exitError) Error() string {
	if e.stderr != "" {
		return e.stderr
	}
	return e.err.Error()
}

// SecretGet fills v with the secret; false when there is none.
func SecretGet(kind string, v any) (bool, error) {
	var data []byte
	if dir := secretsDir(); dir != "" {
		b, err := os.ReadFile(filepath.Join(dir, kind))
		if err != nil {
			return false, nil
		}
		data = b
	} else {
		out, err := secretTool("", "lookup", "application", "nixbook-accounts", "kind", kind)
		var exit *exitError
		if errors.As(err, &exit) {
			// secret-tool exits 1 when nothing matches.
			return false, nil
		}
		if err != nil {
			return false, err
		}
		data = []byte(out)
	}
	if len(strings.TrimSpace(string(data))) == 0 {
		return false, nil
	}
	return json.Unmarshal(data, v) == nil, nil
}

// SecretSet saves v as the secret; nil removes it.
func SecretSet(kind string, v any) error {
	if dir := secretsDir(); dir != "" {
		path := filepath.Join(dir, kind)
		if v == nil {
			if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
				return err
			}
			return nil
		}
		data, err := json.Marshal(v)
		if err != nil {
			return err
		}
		return os.WriteFile(path, data, 0o600)
	}
	attrs := []string{"application", "nixbook-accounts", "kind", kind}
	if v == nil {
		_, err := secretTool("", append([]string{"clear"}, attrs...)...)
		var exit *exitError
		if errors.As(err, &exit) {
			return nil
		}
		return err
	}
	data, err := json.Marshal(v)
	if err != nil {
		return err
	}
	if _, err := secretTool(string(data), append([]string{"store", "--label=nixbook-accounts: " + kind}, attrs...)...); err != nil {
		return Errorf("couldn't save to the keyring: %v", err)
	}
	return nil
}
