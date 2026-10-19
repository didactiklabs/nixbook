// Package local is the local provider: the built-in account's contacts,
// task lists and calendars, kept on this computer only, in
// $XDG_DATA_HOME/nixbook-accounts/local/ (contacts.json, tasks.json,
// calendar.json: the data itself, not a copy). Nothing syncs: a "sync"
// reads the file into the merged copy, a change writes it.
package local

import (
	"crypto/rand"
	"encoding/hex"
	"path/filepath"
	"strings"
	"time"

	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/core"
)

func path(name string) (string, error) {
	dir, err := core.DataDir("local")
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, name), nil
}

func read(name string, v any) (bool, error) {
	p, err := path(name)
	if err != nil {
		return false, err
	}
	return core.ReadFile(p, v)
}

func write(name string, v any) error {
	p, err := path(name)
	if err != nil {
		return err
	}
	return core.WriteFile(p, v)
}

// newID is a short random id.
func newID() string {
	b := make([]byte, 8)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func now() string { return time.Now().UTC().Format(time.RFC3339) }

func str(op map[string]any, key string) (string, bool, error) {
	v, has := op[key]
	if !has {
		return "", false, nil
	}
	if v == nil {
		return "", true, nil
	}
	s, ok := v.(string)
	if !ok {
		return "", true, core.Errorf("`%s` must be a string", key)
	}
	if len(s) > 8192 {
		return "", true, core.Errorf("`%s`: at most 8192 characters", key)
	}
	return strings.TrimRight(s, " \t"), true, nil
}
