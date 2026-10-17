// nixbook-accounts: the shell's accounts backend. The user's accounts
// (Google, CalDAV/CardDAV servers, and the built-in local one kept on this
// computer only), each signed in once, and the services
// merged across them: contacts (the Contacts app and widget, the desktop MCP
// server's `contacts` tool), tasks (the to-do list, the Tasks app, the
// `tasks` tool) and calendars (the shell's calendars and reminders).
package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/calendar"
	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/contacts"
	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/core"
	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/dav"
	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/google"
	_ "github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/local"
	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/registry"
	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/tasks"
)

const usage = `nixbook-accounts: the accounts behind nixbook-shell's contacts and tasks

  nixbook-accounts status                the accounts, the providers' setup, each copy
  nixbook-accounts setup google FILE|--find|--id ID --secret SECRET
                                         Google's OAuth client (Google Cloud, "Desktop
                                         app"): its downloaded JSON, the newest
                                         ~/Downloads/client_secret*.json, or both values
  nixbook-accounts add google [--no-browser]
                                         Google's consent page, the token on 127.0.0.1,
                                         then a first sync (the same email again: that
                                         account signed in anew)
  nixbook-accounts add dav --preset icloud|fastmail|nextcloud|custom [--url URL]
                         [--contacts-url URL] [--calendar-url URL] --username USER
                         [--name NAME] --password-stdin
                                         a CalDAV/CardDAV account (an app password for
                                         iCloud and Fastmail), checked on its server,
                                         then a first sync
  nixbook-accounts remove ACCOUNT        forget an account, its secret and its copies

  nixbook-accounts contacts sync [--account A] [--full]
  nixbook-accounts contacts list [--query Q] [--label L] [--account A] [--starred] [--limit N]
  nixbook-accounts contacts get ID
  nixbook-accounts contacts apply JSON|@FILE|-
                                         {op…} or {ops: […]} (create {account?…}, update,
                                         delete, star, unstar, set_photo {id, photo: an
                                         image file's path, "" removes it}, create_label,
                                         rename_label, delete_label), each on its own
  nixbook-accounts tasks sync [--account A] [--full]
  nixbook-accounts tasks list [--list L] [--account A] [--done]
  nixbook-accounts tasks apply JSON|@FILE|-
                                         {op…} or {ops: […]} (create {list? | account?…},
                                         update, done, undone, move, delete, create_list,
                                         rename_list, delete_list), each on its own
  nixbook-accounts calendar sync [--account A] [--full]
  nixbook-accounts calendar calendars
  nixbook-accounts calendar events --from TIME --to TIME [--calendar C]…
                                         the occurrences between them, series
                                         expanded (TIME: YYYY-MM-DD[THH:MM] or RFC 3339)
  nixbook-accounts calendar apply JSON|@FILE|-
                                         {op…} or {ops: […]} (create {calendar?, summary,
                                         start, end? (all-day: its last day), allDay?,
                                         location?, description?, reminders? (minutes
                                         before), recurrence? (daily, weekdays, weekly,
                                         monthly, yearly, none, RRULE…)}, update {id,
                                         occurrence? (that one only), calendar? (move)…},
                                         delete {id, occurrence?}, show_calendar and
                                         hide_calendar {calendar}: listed and reminded
                                         or not, Google's fetched or not), each on its own

ACCOUNT: an account's id (google-1), name or email; "local" is the built-in one,
kept on this computer only ($XDG_DATA_HOME/nixbook-accounts/local/). Ids are
"<account>:<id>".
Every command prints JSON; exit 2 means sign in (again).
Local copies: $XDG_STATE_HOME/nixbook-accounts/.`

func main() {
	out, err := run(os.Args[1:], os.Stdout)
	if err != nil {
		var auth *core.AuthError
		if errors.As(err, &auth) {
			emit(map[string]any{"error": err.Error(), "auth": true})
			os.Exit(2)
		}
		emit(map[string]any{"error": err.Error()})
		os.Exit(1)
	}
	if out != nil {
		emit(out)
	}
}

func emit(v any) {
	enc := json.NewEncoder(os.Stdout)
	enc.SetEscapeHTML(false)
	_ = enc.Encode(v)
}

// flag takes `name value` out of args.
func flag(args *[]string, name string) (string, error) {
	i := slices.Index(*args, name)
	if i < 0 {
		return "", nil
	}
	if i+1 >= len(*args) {
		return "", core.Errorf("%s needs a value", name)
	}
	v := (*args)[i+1]
	*args = slices.Delete(*args, i, i+2)
	return v, nil
}

// flags takes several `name value` out of args.
func flags(args *[]string, names ...string) (map[string]string, error) {
	out := map[string]string{}
	for _, n := range names {
		v, err := flag(args, n)
		if err != nil {
			return nil, err
		}
		out[n] = v
	}
	return out, nil
}

func readRequest(arg string) (any, error) {
	var data []byte
	var err error
	switch {
	case arg == "-":
		data, err = io.ReadAll(os.Stdin)
	case strings.HasPrefix(arg, "@"):
		data, err = os.ReadFile(arg[1:])
	default:
		data = []byte(arg)
	}
	if err != nil {
		return nil, core.Errorf("can't read the request: %v", err)
	}
	var v any
	if json.Unmarshal(data, &v) != nil {
		return nil, core.Errorf("the request isn't JSON")
	}
	return v, nil
}

func run(argv []string, stdout io.Writer) (any, error) {
	if len(argv) == 0 || slices.Contains([]string{"-h", "--help", "help"}, argv[0]) {
		fmt.Fprintln(stdout, usage)
		return nil, nil
	}
	cmd, args := argv[0], argv[1:]
	switch cmd {
	case "status":
		return status(), nil
	case "setup":
		if len(args) == 0 || args[0] != "google" {
			return nil, core.Errorf("setup google FILE|--find|--id ID --secret SECRET")
		}
		args = args[1:]
		f, err := flags(&args, "--id", "--secret")
		if err != nil {
			return nil, err
		}
		file := ""
		if len(args) > 0 {
			file = args[0]
		}
		if file == "" && f["--id"] == "" && f["--secret"] == "" {
			return nil, core.Errorf("setup google FILE, --find, or --id ID --secret SECRET")
		}
		c, err := google.SetupClient(file, f["--id"], f["--secret"])
		if err != nil {
			return nil, err
		}
		return map[string]any{"ok": true, "client": truncate(c.ID, 12)}, nil
	case "add":
		if len(args) == 0 || (args[0] != "google" && args[0] != "dav") {
			return nil, core.Errorf("add google [--no-browser], or add dav --preset … --username … --password-stdin")
		}
		if args[0] == "dav" {
			return addDav(args[1:])
		}
		a, err := google.Login(!slices.Contains(args, "--no-browser"), stdout)
		if err != nil {
			return nil, err
		}
		return firstSync(a), nil
	case "remove":
		if len(args) == 0 {
			return nil, core.Errorf("remove ACCOUNT")
		}
		a, err := registry.Get(args[0])
		if err != nil {
			return nil, err
		}
		if a.Provider == "google" {
			google.Revoke(a)
		}
		if _, err := registry.Remove(a.ID); err != nil {
			return nil, err
		}
		if err := contacts.Forget(a.ID); err != nil {
			return nil, err
		}
		if err := calendar.Forget(a.ID); err != nil {
			return nil, err
		}
		return map[string]any{"ok": true, "removed": a.ID}, tasks.Forget(a.ID)
	case "contacts":
		return runContacts(args)
	case "tasks":
		return runTasks(args)
	case "calendar":
		return runCalendar(args)
	}
	return nil, core.Errorf("unknown command '%s' (see --help)", cmd)
}

func addDav(args []string) (any, error) {
	f, err := flags(&args, "--preset", "--url", "--contacts-url", "--calendar-url", "--username", "--name")
	if err != nil {
		return nil, err
	}
	if !slices.Contains(args, "--password-stdin") {
		return nil, core.Errorf("the password comes on stdin (--password-stdin), never in the arguments")
	}
	data, err := io.ReadAll(io.LimitReader(os.Stdin, 4096))
	if err != nil {
		return nil, core.Errorf("can't read the password: %v", err)
	}
	preset := f["--preset"]
	if preset == "" {
		preset = "custom"
	}
	a, err := dav.Add(dav.AddOptions{
		Preset: preset, URL: f["--url"], ContactsURL: f["--contacts-url"], CalendarURL: f["--calendar-url"],
		Username: f["--username"], Name: f["--name"], Password: strings.TrimRight(string(data), "\r\n"),
	})
	if err != nil {
		return nil, err
	}
	return firstSync(a), nil
}

// firstSync fills the copies with a new account's data.
func firstSync(a registry.Account) map[string]any {
	out := map[string]any{"ok": true, "account": a}
	if contacts.Supported(a) {
		if res, err := contacts.Sync(a.ID, true); err != nil {
			out["contactsError"] = err.Error()
		} else {
			out["contacts"] = res
		}
	}
	if tasks.Supported(a) {
		if res, err := tasks.Sync(a.ID, true); err != nil {
			out["tasksError"] = err.Error()
		} else {
			out["tasks"] = res
		}
	}
	if calendar.Supported(a) {
		if res, err := calendar.Sync(a.ID, true); err != nil {
			out["calendarError"] = err.Error()
		} else {
			out["calendar"] = res
		}
	}
	return out
}

func runContacts(argv []string) (any, error) {
	if len(argv) == 0 {
		return nil, core.Errorf("contacts sync|list|get|apply (see --help)")
	}
	cmd, args := argv[0], argv[1:]
	switch cmd {
	case "sync":
		account, err := flag(&args, "--account")
		if err != nil {
			return nil, err
		}
		return contacts.Sync(account, slices.Contains(args, "--full"))
	case "list":
		f, err := flags(&args, "--query", "--label", "--account", "--limit")
		if err != nil {
			return nil, err
		}
		limit := 0
		if f["--limit"] != "" {
			if limit, err = strconv.Atoi(f["--limit"]); err != nil || limit < 0 {
				return nil, core.Errorf("--limit must be a number")
			}
		}
		return contacts.List(f["--query"], f["--label"], f["--account"], slices.Contains(args, "--starred"), limit)
	case "get":
		if len(args) == 0 {
			return nil, core.Errorf("contacts get ID")
		}
		return contacts.Get(args[0])
	case "apply":
		if len(args) == 0 {
			return nil, core.Errorf("contacts apply JSON|@FILE|-")
		}
		req, err := readRequest(args[0])
		if err != nil {
			return nil, err
		}
		return contacts.Apply(req)
	}
	return nil, core.Errorf("unknown contacts command '%s' (see --help)", cmd)
}

func runTasks(argv []string) (any, error) {
	if len(argv) == 0 {
		return nil, core.Errorf("tasks sync|list|apply (see --help)")
	}
	cmd, args := argv[0], argv[1:]
	switch cmd {
	case "sync":
		account, err := flag(&args, "--account")
		if err != nil {
			return nil, err
		}
		return tasks.Sync(account, slices.Contains(args, "--full"))
	case "list":
		f, err := flags(&args, "--list", "--account")
		if err != nil {
			return nil, err
		}
		return tasks.ListTasks(f["--list"], f["--account"], slices.Contains(args, "--done"))
	case "apply":
		if len(args) == 0 {
			return nil, core.Errorf("tasks apply JSON|@FILE|-")
		}
		req, err := readRequest(args[0])
		if err != nil {
			return nil, err
		}
		return tasks.Apply(req)
	}
	return nil, core.Errorf("unknown tasks command '%s' (see --help)", cmd)
}

func runCalendar(argv []string) (any, error) {
	if len(argv) == 0 {
		return nil, core.Errorf("calendar sync|calendars|events|apply (see --help)")
	}
	cmd, args := argv[0], argv[1:]
	switch cmd {
	case "sync":
		account, err := flag(&args, "--account")
		if err != nil {
			return nil, err
		}
		return calendar.Sync(account, slices.Contains(args, "--full"))
	case "calendars":
		c := calendar.Load()
		return map[string]any{"syncedAt": c.SyncedAt, "error": c.Error, "calendars": c.Calendars}, nil
	case "events":
		f, err := flags(&args, "--from", "--to")
		if err != nil {
			return nil, err
		}
		cals := []string{}
		for {
			v, err := flag(&args, "--calendar")
			if err != nil {
				return nil, err
			}
			if v == "" {
				break
			}
			cals = append(cals, v)
		}
		if f["--from"] == "" || f["--to"] == "" {
			return nil, core.Errorf("calendar events --from TIME --to TIME")
		}
		from, _, err := calendar.InputTime(f["--from"])
		if err != nil {
			return nil, err
		}
		to, _, err := calendar.InputTime(f["--to"])
		if err != nil {
			return nil, err
		}
		if !to.After(from) || to.Sub(from) > 400*24*time.Hour {
			return nil, core.Errorf("--to must be after --from, at most 400 days")
		}
		c := calendar.Load()
		return map[string]any{
			"syncedAt": c.SyncedAt, "error": c.Error, "calendars": c.Calendars,
			"events": calendar.Occurrences(from, to, cals),
		}, nil
	case "apply":
		if len(args) == 0 {
			return nil, core.Errorf("calendar apply JSON|@FILE|-")
		}
		req, err := readRequest(args[0])
		if err != nil {
			return nil, err
		}
		return calendar.Apply(req)
	}
	return nil, core.Errorf("unknown calendar command '%s' (see --help)", cmd)
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "…"
}

func status() map[string]any {
	out := map[string]any{"contacts": contacts.Summary(), "tasks": tasks.Summary(), "calendar": calendar.Summary()}
	googleSetup := map[string]any{"configured": false, "console": google.ConsoleURL, "apis": google.APILibrary}
	if ok, err := google.Configured(); err != nil {
		out["error"] = err.Error()
	} else {
		googleSetup["configured"] = ok
	}
	out["providers"] = map[string]any{"google": googleSetup, "dav": map[string]any{"presets": dav.Presets}}
	accounts := []map[string]any{}
	for _, a := range registry.List() {
		connected := false
		switch a.Provider {
		case "google":
			connected = google.Connected(a)
		case "dav":
			connected = dav.Connected(a)
		case "local":
			connected = true
		}
		accounts = append(accounts, map[string]any{
			"id": a.ID, "provider": a.Provider, "name": a.Name, "email": a.Email, "url": a.URL, "preset": a.Preset,
			"username": a.Username, "contacts": contacts.Supported(a), "tasks": tasks.Supported(a),
			"calendar":      calendar.Supported(a),
			"calendarError": calendar.AccountError(a.ID),
			"connected":     connected,
			"contactsError": contacts.AccountError(a.ID),
			"tasksError":    tasks.AccountError(a.ID),
		})
	}
	out["accounts"] = accounts
	return out
}
