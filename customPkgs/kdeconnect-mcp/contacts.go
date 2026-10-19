package main

// The phone's contacts as KDE Connect's contacts plugin keeps them: a vCard
// per contact in $XDG_DATA_HOME/kpeoplevcard/kdeconnect-<device id>/.

import (
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

type Contact struct {
	Name   string   `json:"name"`
	Phones []string `json:"phones"`
}

func dataHome() string {
	if d := os.Getenv("XDG_DATA_HOME"); d != "" {
		return d
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".local", "share")
}

func loadContacts(deviceID string) []Contact {
	files, _ := filepath.Glob(filepath.Join(dataHome(), "kpeoplevcard", "kdeconnect-"+deviceID, "*.vcf"))
	var out []Contact
	for _, f := range files {
		b, err := os.ReadFile(f)
		if err != nil {
			continue
		}
		if c := parseVCard(string(b)); c.Name != "" && len(c.Phones) > 0 {
			out = append(out, c)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out
}

func parseVCard(s string) Contact {
	// Folded lines (RFC 6350 §3.2) unfolded first.
	s = strings.NewReplacer("\r\n ", "", "\r\n\t", "", "\n ", "", "\n\t", "").Replace(s)
	var c Contact
	for _, line := range strings.Split(strings.ReplaceAll(s, "\r\n", "\n"), "\n") {
		key, val, ok := strings.Cut(line, ":")
		if !ok {
			continue
		}
		name, _, _ := strings.Cut(key, ";")
		switch strings.ToUpper(name) {
		case "FN":
			c.Name = strings.ReplaceAll(val, `\,`, ",")
		case "TEL":
			if v := strings.TrimPrefix(val, "tel:"); v != "" {
				c.Phones = append(c.Phones, v)
			}
		}
	}
	return c
}

var nonDigit = regexp.MustCompile(`\D`)

// sameNumber compares phone numbers by their last 9 digits: "+33 6 12 34
// 56 78" and "06 12 34 56 78" are the same.
func sameNumber(a, b string) bool {
	a, b = nonDigit.ReplaceAllString(a, ""), nonDigit.ReplaceAllString(b, "")
	if a == "" || b == "" {
		return a == b
	}
	n := min(9, len(a), len(b))
	return a[len(a)-n:] == b[len(b)-n:]
}

func nameFor(contacts []Contact, number string) string {
	for _, c := range contacts {
		for _, p := range c.Phones {
			if sameNumber(p, number) {
				return c.Name
			}
		}
	}
	return ""
}
