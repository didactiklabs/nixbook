package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"syscall"
	"time"
)

// Where it keeps things: the inbox and the runs (small JSON files the shell
// watches) in $XDG_STATE_HOME/nixbook-shell/improve/, its clone of the
// repository and each run's logs in $XDG_DATA_HOME/nixbook-shell/improve/.
func xdg(env, fallback string) string {
	if v := os.Getenv(env); v != "" {
		return v
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, fallback)
}

func stateDir() string {
	return filepath.Join(xdg("XDG_STATE_HOME", ".local/state"), "nixbook-shell", "improve")
}

func dataDir() string {
	return filepath.Join(xdg("XDG_DATA_HOME", ".local/share"), "nixbook-shell", "improve")
}

func configPath() string {
	return filepath.Join(xdg("XDG_CONFIG_HOME", ".config"), "nixbook-shell", "config.json")
}

func readJSON(path string, v any) error {
	b, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	return json.Unmarshal(b, v)
}

// writeJSON replaces the file whole: the shell never reads half of it.
func writeJSON(path string, v any) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	b, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, append(b, '\n'), 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

// lock takes an flock on name in the state dir: blocking for the files'
// read-modify-write, non-blocking (errBusy) for the one run at a time.
var errBusy = errors.New("busy")

func lock(name string, wait bool) (func(), error) {
	if err := os.MkdirAll(stateDir(), 0o700); err != nil {
		return nil, err
	}
	f, err := os.OpenFile(filepath.Join(stateDir(), name), os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return nil, err
	}
	how := syscall.LOCK_EX
	if !wait {
		how |= syscall.LOCK_NB
	}
	if err := syscall.Flock(int(f.Fd()), how); err != nil {
		f.Close()
		if errors.Is(err, syscall.EWOULDBLOCK) {
			return nil, errBusy
		}
		return nil, err
	}
	var once sync.Once
	return func() { once.Do(func() { syscall.Flock(int(f.Fd()), syscall.LOCK_UN); f.Close() }) }, nil
}

func nowMs() int64 { return time.Now().UnixMilli() }

func errorf(format string, a ...any) error { return fmt.Errorf(format, a...) }
