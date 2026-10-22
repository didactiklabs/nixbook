package main

import (
	"strings"
	"testing"
)

func TestMatchGlob(t *testing.T) {
	for _, c := range []struct {
		glob, path string
		want       bool
	}{
		{".github/**", ".github/workflows/checks.yaml", true},
		{"**/*.md", "README.md", true},
		{"**/*.md", "docs/nixbook-shell/agents.md", true},
		{"**/AGENTS.md", "AGENTS.md", true},
		{"nixbook-shell/*.nix", "nixbook-shell/hm-module.nix", true},
		{"nixbook-shell/*.nix", "nixbook-shell/accounts/x.nix", false},
		{"tests/**", "nixbook-shell/tests/x.sh", false},
		{"docs/**", "docs.md", false},
		{"hive.nix", "profiles/hive.nix", false},
	} {
		if got := matchGlob(c.glob, c.path); got != c.want {
			t.Errorf("matchGlob(%q, %q) = %v", c.glob, c.path, got)
		}
	}
}

func TestCheckDiff(t *testing.T) {
	lim := Limits{Files: 3, Lines: 20}
	ok := []Change{{Path: "nixbook-shell/src/modules/ii/bar/Clock.qml", Status: "M", Added: 3, Deleted: 2}}
	if why := checkDiff(ok, lim); len(why) != 0 {
		t.Fatalf("a small fix refused: %v", why)
	}
	for name, cs := range map[string][]Change{
		"nothing":        nil,
		"forbidden":      {{Path: ".github/workflows/checks.yaml", Status: "M", Added: 1}},
		"own code":       {{Path: "nixbook-shell/improve/guard.go", Status: "M", Added: 1}},
		"sandbox":        {{Path: "nixbook-shell/scripts/agent-desktop.sh", Status: "M", Added: 1}},
		"agents.md":      {{Path: "AGENTS.md", Status: "M", Added: 1}},
		"too many lines": {{Path: "a.qml", Status: "M", Added: 15, Deleted: 6}},
		"too many files": {{Path: "a", Status: "M"}, {Path: "b", Status: "M"}, {Path: "c", Status: "M"}, {Path: "d", Status: "M"}},
		"binary":         {{Path: "assets/x.png", Status: "M", Binary: true}},
		"deleted":        {{Path: "a.qml", Status: "D", Deleted: 3}},
		"new file":       {{Path: "nixbook-shell/src/New.qml", Status: "A", Added: 3}},
	} {
		if why := checkDiff(cs, lim); len(why) == 0 {
			t.Errorf("%s: not refused", name)
		}
	}
	if why := checkDiff([]Change{{Path: "docs/x.md", Status: "A", Added: 4}}, lim); len(why) != 0 {
		t.Errorf("a new Markdown file refused: %v", why)
	}
}

func TestAutoMergeable(t *testing.T) {
	paths := defaults().AutoMergePaths
	if !autoMergeable([]Change{{Path: "docs/nixbook-shell/settings.md"}, {Path: "README.md"}}, paths) {
		t.Error("docs only: not auto-mergeable")
	}
	if autoMergeable([]Change{{Path: "docs/x.md"}, {Path: "nixbook-shell/src/shell.qml"}}, paths) {
		t.Error("QML: auto-mergeable")
	}
	if autoMergeable([]Change{{Path: "nixbook-shell/scripts/desktop-mcp.py"}}, []string{"**"}) {
		t.Error("a sensitive file: auto-mergeable")
	}
}

func TestCommitMessage(t *testing.T) {
	a := Answer{
		Outcome: "fixed", Type: "polish", Scope: "Nixbook Shell", Title: "The clock keeps its seconds after a theme switch.",
		Body: "The clock widget dropped its seconds when the theme changed, because its format was read once at start. " +
			"It now follows the setting, so switching themes keeps the seconds shown.",
	}
	it := Item{ID: "0123abcd", Kind: "qml", Count: 4}
	msg := commitMessage(a, it)
	if why := checkMessage(msg); len(why) != 0 {
		t.Fatalf("its own message refused: %v\n%s", why, msg)
	}
	if !strings.HasPrefix(msg, "polish(nixbook-shell): the clock keeps its seconds after a theme switch\n") {
		t.Errorf("title: %q", firstLine(msg))
	}
	for _, l := range strings.Split(msg, "\n") {
		if len([]rune(l)) > 72 {
			t.Errorf("line longer than 72: %q", l)
		}
	}
	a.Title = "a thumbnail with no source no longer warns about unassignable undefined values"
	long := firstLine(commitMessage(a, it))
	if len([]rune(long)) > 72 || strings.Contains(long, "…") || strings.HasSuffix(long, " un") {
		t.Errorf("a long title: %q", long)
	}
	for _, bad := range []string{
		"feat(nixbook-shell): a new widget\n\n" + strings.Repeat("word ", 30) + "\n\nAgent-Fix: 0123abcd",
		"fix(nixbook-shell): short body\n\nToo short.\n\nAgent-Fix: 0123abcd",
		"fix(nixbook-shell): no trailer here\n\n" + strings.Repeat("word ", 30),
	} {
		if len(checkMessage(bad)) == 0 {
			t.Errorf("accepted: %q", firstLine(bad))
		}
	}
}

const sampleLog = `  WARN scene: @modules/common/widgets/ThumbnailImage.qml[18:5]: Unable to assign [undefined] to QString
  WARN scene: QML FileView at @services/Ai.qml[64:5]: Read of /home/u/.config/nixbook-shell/system-context.md failed: File does not exist.
  WARN scene: @modules/ii/bar/Clock.qml[40:9]: TypeError: Cannot read property 'length' of undefined
  WARN: Could not load icon "image-missing" at size QSize(18, 18) from request
  WARN scene: @modules/ii/bar/Clock.qml[41:9]: TypeError: Cannot read property 'length' of undefined`

func TestParseWarnings(t *testing.T) {
	ws := parseWarnings(sampleLog)
	if len(ws) != 3 {
		t.Fatalf("got %d warnings: %+v", len(ws), ws)
	}
	if ws[0].File != "nixbook-shell/src/modules/common/widgets/ThumbnailImage.qml" || ws[0].Line != 18 {
		t.Errorf("first: %+v", ws[0])
	}
	u, counts := uniqueWarnings(ws)
	if len(u) != 2 || counts[u[0].key()] != 2 {
		t.Errorf("unique: %+v %v", u, counts)
	}
	// Moved lines are the same warning; one more is new.
	after := parseWarnings(strings.ReplaceAll(sampleLog, "[40:9]", "[44:9]") +
		"\n  WARN scene: @shell.qml[3:1]: ReferenceError: foo is not defined")
	added := newWarnings(ws, after)
	if len(added) != 1 || added[0].File != "nixbook-shell/src/shell.qml" {
		t.Errorf("new: %+v", added)
	}
	if n := normalizeMsg("Cannot open: file:///home/u/x 12.png at 0x55aa"); strings.Contains(n, "/home") || strings.Contains(n, "0x55") {
		t.Errorf("normalized: %q", n)
	}
}

func TestInbox(t *testing.T) {
	var in Inbox
	now := int64(1_000_000_000_000)
	in.add("qml", "qml:a", "warning a", "a.qml", 2, now)
	if in.pick(now) != nil {
		t.Fatal("a warning seen twice is ripe")
	}
	in.add("qml", "qml:a", "warning a", "a.qml", 1, now+1)
	if len(in.Items) != 1 || in.Items[0].Count != 3 {
		t.Fatalf("not counted up: %+v", in.Items)
	}
	in.add("user", "user:x", "the bar's clock is cut off", "", 1, now+2)
	if p := in.pick(now + 3); p == nil || p.Kind != "user" {
		t.Fatalf("the user's report isn't first: %+v", p)
	}
	in.find(in.Items[1].ID).Status = "skipped"
	in.Items[1].Tried, in.Items[1].TriedCount = now, 1
	if in.Items[1].ripe(now + 1000) {
		t.Error("a skipped item ripe at once")
	}
	in.Items[1].Count = 2
	if !in.Items[1].ripe(now + retryAfterMs + 1) {
		t.Error("a skipped item seen again a week later isn't ripe")
	}
	in.find(in.Items[0].ID).Status = "dropped"
	in.add("qml", "qml:a", "warning a", "a.qml", 5, now+5)
	if in.Items[0].Status != "dropped" {
		t.Error("a dropped item came back")
	}
	for i := 0; i < inboxMax+5; i++ {
		in.add("crash", "crash:"+string(rune('a'+i%26))+string(rune('a'+i/26)), "x", "", 1, now+int64(10+i))
	}
	if len(in.Items) != inboxMax {
		t.Errorf("%d items kept", len(in.Items))
	}
}

func TestSuspect(t *testing.T) {
	r := Run{
		Started: 100, Files: []Change{{Path: "nixbook-shell/src/modules/ii/bar/Clock.qml"}},
		Before: parseWarnings(`WARN scene: @modules/ii/bar/Clock.qml[2:1]: TypeError: x is not a function`),
	}
	ws := parseWarnings(`WARN scene: @modules/ii/bar/Clock.qml[9:1]: TypeError: x is not a function
WARN scene: @shell.qml[3:1]: ReferenceError: foo is not defined`)
	if why := suspect(r, ws, 0, Inbox{}); why != "" {
		t.Errorf("an old warning, another file's: %s", why)
	}
	ws = append(ws, parseWarnings(`WARN scene: @modules/ii/bar/Clock.qml[5:1]: ReferenceError: y is not defined`)...)
	if why := suspect(r, ws, 0, Inbox{}); !strings.Contains(why, "y is not defined") {
		t.Errorf("a new warning in its file: %q", why)
	}
	var known Inbox
	known.add("qml", "qml:"+ws[2].key(), "", "", 1, 50)
	if why := suspect(r, ws, 0, known); why != "" {
		t.Errorf("printed before the fix too: %s", why)
	}
	if why := suspect(r, nil, 2, Inbox{}); !strings.Contains(why, "restarted 2 times") {
		t.Errorf("restarts: %q", why)
	}
}

func TestGhRepo(t *testing.T) {
	for url, want := range map[string]string{
		"https://github.com/didactiklabs/nixbook":      "didactiklabs/nixbook",
		"https://github.com/didactiklabs/nixbook.git/": "didactiklabs/nixbook",
		"git@github.com:didactiklabs/nixbook.git":      "didactiklabs/nixbook",
		"https://gitlab.com/a/b":                       "",
		"":                                             "",
	} {
		if got := ghRepo(url); got != want {
			t.Errorf("ghRepo(%q) = %q", url, got)
		}
	}
}

func TestWrap(t *testing.T) {
	got := wrap("one two three four five six\n\n- a list item that goes on and on", 14)
	want := "one two three\nfour five six\n\n- a list item\n  that goes on\n  and on"
	if got != want {
		t.Errorf("wrap:\n%s\nwant:\n%s", got, want)
	}
}

func TestOwned(t *testing.T) {
	o := owned{
		system: map[string]bool{"nixos-upgrade-manual": true}, user: map[string]bool{"nixbook-habits": true, "nixbook-agent-desktop@": true},
		packages: []string{"youtube-music-mcp"},
	}
	for _, c := range []struct {
		scope, unit string
		want        bool
	}{
		{"user", "nixbook-habits.service", true},
		{"user", "nixbook-agent-desktop@2.service", true},
		{"user", "pipewire.service", false},
		{"system", "nixos-upgrade-manual.service", true},
		{"system", "home-manager-khoa.service", true},
		{"system", "bluetooth.service", false},
		{"user", "nixos-upgrade-manual.service", false},
	} {
		if got := o.unit(c.scope, c.unit); got != c.want {
			t.Errorf("unit(%s, %s) = %v", c.scope, c.unit, got)
		}
	}
	if n := storeName("/nix/store/abc123-youtube-music-mcp-0.4.1/bin/youtube-music-mcp"); n != "youtube-music-mcp-0.4.1" {
		t.Errorf("storeName: %q", n)
	}
	if storeName("/usr/bin/zen") != "" {
		t.Error("storeName outside the store")
	}
}

func TestInfoNeverRipe(t *testing.T) {
	var in Inbox
	in.add("info", "info:kernel:x", "Kernel: x", "", 5, 1)
	in.add("ci", "ci:Checks", "CI fails", "", 1, 1)
	if p := in.pick(2); p == nil || p.Kind != "ci" {
		t.Fatalf("picked %+v", p)
	}
	in.find(itemID("ci:Checks")).Status = "pr"
	if p := in.pick(2); p != nil {
		t.Errorf("info picked: %+v", p)
	}
}

func TestAutoMergeWhy(t *testing.T) {
	qml := []Change{{Path: "nixbook-shell/src/modules/ii/bar/Clock.qml"}}
	docs := []Change{{Path: "docs/x.md"}}
	sensitive := []Change{{Path: "nixbook-shell/src/services/Ai.qml"}}
	cfg := defaults()
	if autoMergeWhy(cfg, qml) != "" || autoMergeWhy(cfg, docs) != "" {
		t.Error("merged on its own with both switches off")
	}
	cfg.AutoMerge = true
	if autoMergeWhy(cfg, docs) == "" || autoMergeWhy(cfg, qml) != "" {
		t.Error("docs-only: wrong")
	}
	cfg.AutoMergeFixes = true
	if autoMergeWhy(cfg, qml) == "" {
		t.Error("every fix: a QML fix not merged")
	}
	if autoMergeWhy(cfg, sensitive) != "" || autoMergeWhy(cfg, append(qml, sensitive...)) != "" {
		t.Error("every fix: a sensitive file merged on its own")
	}
}

func TestFailLines(t *testing.T) {
	out := "== suite\nok   - one\nFAIL - two\n       expected: a\n       actual:   b\nok   - three\nFAIL - four\n"
	want := "FAIL - two\n       expected: a\n       actual:   b\nFAIL - four"
	if got := failLines(out); got != want {
		t.Errorf("failLines = %q, want %q", got, want)
	}
	if got := failLines("ok   - one\n"); got != "" {
		t.Errorf("failLines without failures = %q", got)
	}
}
