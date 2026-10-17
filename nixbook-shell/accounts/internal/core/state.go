// Package core is what every provider and service of nixbook-accounts
// shares: the state directory and its locks, the keyring, the HTTP calls.
package core

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"syscall"
)

// StateDir is $XDG_STATE_HOME/nixbook-accounts: the accounts, each service's local copy,
// which the shell watches, and the lock.
func StateDir() (string, error) {
	base := os.Getenv("XDG_STATE_HOME")
	if base == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		base = filepath.Join(home, ".local", "state")
	}
	dir := filepath.Join(base, "nixbook-accounts")
	return dir, os.MkdirAll(dir, 0o700)
}

// StatePath is a file in the state directory.
func StatePath(name string) (string, error) {
	dir, err := StateDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, name), nil
}

// Lock holds a service's lock until the returned function runs: one writer
// of its copy at a time, as the shell and agents run this side by side;
// another service (a contacts sync, a task ticked) doesn't wait.
func Lock(service string) (func(), error) {
	path, err := StatePath(service + ".lock")
	if err != nil {
		return nil, err
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return nil, err
	}
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != nil {
		f.Close()
		return nil, err
	}
	return func() {
		syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
		f.Close()
	}, nil
}

// ReadJSON fills v from the state file; false when it is missing or broken.
func ReadJSON(name string, v any) bool {
	path, err := StatePath(name)
	if err != nil {
		return false
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	return json.Unmarshal(data, v) == nil
}

// WriteJSON replaces the state file at once (readers never see half of it).
func WriteJSON(name string, v any) error {
	path, err := StatePath(name)
	if err != nil {
		return err
	}
	data, err := json.Marshal(v)
	if err != nil {
		return err
	}
	tmp := fmt.Sprintf("%s.%d.tmp", path, os.Getpid())
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

// DataDir is $XDG_DATA_HOME/nixbook-accounts/<name>: data that exists
// nowhere else (the local account's), unlike the state directory's copies.
func DataDir(name string) (string, error) {
	base := os.Getenv("XDG_DATA_HOME")
	if base == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		base = filepath.Join(home, ".local", "share")
	}
	dir := filepath.Join(base, "nixbook-accounts", name)
	return dir, os.MkdirAll(dir, 0o700)
}

// ReadFile fills v from a JSON file; false when it is missing.
func ReadFile(path string, v any) (bool, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	if err := json.Unmarshal(data, v); err != nil {
		return false, Errorf("%s is damaged: %v", path, err)
	}
	return true, nil
}

// WriteFile replaces a JSON file at once.
func WriteFile(path string, v any) error {
	data, err := json.MarshalIndent(v, "", " ")
	if err != nil {
		return err
	}
	tmp := fmt.Sprintf("%s.%d.tmp", path, os.Getpid())
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

// RemoveState deletes a state file, if there.
func RemoveState(name string) error {
	path, err := StatePath(name)
	if err != nil {
		return err
	}
	if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return nil
}
