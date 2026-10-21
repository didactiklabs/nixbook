package main

import (
	"regexp"
	"slices"
	"strconv"
	"strings"
)

// The shell's QML warnings, as Quickshell prints them (its journal, the
// headless load of tests/shell-loads.sh):
//
//	WARN scene: @modules/common/widgets/ThumbnailImage.qml[18:5]: Unable to assign [undefined] to QString
//
// Only the ones that are bugs in the code: a missing optional file, an icon
// the theme lacks or no network are the machine's, not something to fix.
type Warning struct {
	File string `json:"file"` // in the repository: nixbook-shell/src/…
	Line int    `json:"line"`
	Msg  string `json:"msg"` // without paths and numbers: the same bug matches
}

var (
	warnRe = regexp.MustCompile(`@([A-Za-z0-9_./-]+\.qml)\[(\d+):\d+\]: (.+)$`)
	bugRe  = regexp.MustCompile(`TypeError|ReferenceError|SyntaxError|RangeError|Unable to assign|Cannot assign|` +
		`is not a function|is not defined|is not a type|Cannot read propert|Cannot call method|non-existent property|` +
		`Binding loop|depends on non-NOTIFYable|Could not convert argument|Unable to determine callable overload|` +
		`Invalid property assignment|has no member|Cannot anchor|Detected anchors`)
	pathRe = regexp.MustCompile(`(?:file://)?/[^\s'"\]\)]+`)
	numRe  = regexp.MustCompile(`\b0x[0-9a-fA-F]+\b|\b\d+\b`)
)

func normalizeMsg(s string) string {
	s = pathRe.ReplaceAllString(s, "<path>")
	s = numRe.ReplaceAllString(s, "N")
	return clip(s, 300)
}

func parseWarnings(log string) []Warning {
	var out []Warning
	for _, line := range strings.Split(log, "\n") {
		m := warnRe.FindStringSubmatch(line)
		if m == nil || !bugRe.MatchString(m[3]) {
			continue
		}
		n, _ := strconv.Atoi(m[2])
		out = append(out, Warning{File: "nixbook-shell/src/" + m[1], Line: n, Msg: normalizeMsg(m[3])})
	}
	return out
}

func (w Warning) key() string { return w.File + "\t" + w.Msg }

// newWarnings: what after has more of than before. Lines aren't compared: a
// fix in a file moves its other warnings.
func newWarnings(before, after []Warning) []Warning {
	seen := map[string]int{}
	for _, w := range before {
		seen[w.key()]++
	}
	var out []Warning
	for _, w := range after {
		if seen[w.key()] > 0 {
			seen[w.key()]--
			continue
		}
		out = append(out, w)
	}
	return out
}

// uniqueWarnings: each bug once, with how often it was printed.
func uniqueWarnings(ws []Warning) ([]Warning, map[string]int) {
	counts := map[string]int{}
	var out []Warning
	for _, w := range ws {
		if counts[w.key()] == 0 {
			out = append(out, w)
		}
		counts[w.key()]++
	}
	slices.SortStableFunc(out, func(a, b Warning) int { return counts[b.key()] - counts[a.key()] })
	return out, counts
}
