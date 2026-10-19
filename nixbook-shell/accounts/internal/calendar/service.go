// Package calendar is the calendars of every account, merged: one local
// copy (events.json in the state directory) kept in sync by each account's
// provider (Google Calendar, CalDAV), holding events as their providers
// keep them (a recurring series once, with its recurrence lines, its
// changed or cancelled occurrences beside it). Reading a time range
// expands the series into occurrences (`Occurrences`): the shell's
// calendars, its reminders and agents read those. Changes go to the
// account's provider first, its answer landing in the copy. Ids are global
// ("<account>:<provider's id>").
package calendar

import (
	"slices"
	"strings"
	"time"

	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/core"
	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/registry"
)

// CacheFile is the local copy's name in the state directory.
const CacheFile = "events.json"

// MaxOps is the most changes one apply runs.
const MaxOps = 50

// Calendar is one calendar of an account.
type Calendar struct {
	ID      string `json:"id"`
	Account string `json:"account"`
	Name    string `json:"name"`
	// #rrggbb, or "".
	Color    string `json:"color"`
	Primary  bool   `json:"primary"`
	ReadOnly bool   `json:"readOnly"`
	Order    int    `json:"order"`
	// Minutes before an event, for events with no reminders of their own.
	DefaultReminders []int `json:"defaultReminders"`
	// Turned off in the shell (show_calendar, hide_calendar), else as its
	// provider has it (Google: unticked or hidden in Google Calendar): its
	// events aren't listed, nor reminded, and Google's aren't fetched.
	Hidden bool `json:"hidden"`
}

// Event is an event as its provider keeps it: a single one, a recurring
// series (Recurrence), or one changed or cancelled occurrence of a series
// (RecurringID, OriginalStart).
type Event struct {
	ID          string `json:"id"`
	Account     string `json:"account"`
	CalendarID  string `json:"calendarId"`
	Summary     string `json:"summary"`
	Description string `json:"description"`
	Location    string `json:"location"`
	// RFC 3339 for a timed event, YYYY-MM-DD for an all-day one (End
	// exclusive: the day after).
	Start  string `json:"start"`
	End    string `json:"end"`
	AllDay bool   `json:"allDay"`
	// The IANA zone a series repeats in ("" local).
	TimeZone string `json:"timeZone"`
	// A series' RRULE/EXDATE/RDATE lines (iCalendar's form).
	Recurrence []string `json:"recurrence,omitempty"`
	// An occurrence's series and its original start (RFC 3339 or date).
	RecurringID   string `json:"recurringId,omitempty"`
	OriginalStart string `json:"originalStart,omitempty"`
	// A cancelled occurrence (of a series kept elsewhere).
	Cancelled  bool   `json:"cancelled,omitempty"`
	MeetingURL string `json:"meetingUrl"`
	// Minutes before; nil: the calendar's default reminders.
	Reminders []int  `json:"reminders"`
	Updated   string `json:"updated"`
}

// Section is one account's part of the copy, with the provider's own ids.
type Section struct {
	SyncToken string
	SyncedAt  int64
	Error     string
	Calendars []Calendar
	Events    []Event
	// The calendars the user turned on (true) or off, by id.
	Shown map[string]bool
}

// Visible says whether a calendar is shown: as the user chose, else
// byDefault (the provider's own choice).
func (s *Section) Visible(id string, byDefault bool) bool {
	if v, ok := s.Shown[id]; ok {
		return v
	}
	return byDefault
}

// Upsert puts the event in, replacing the one with its id.
func (s *Section) Upsert(e Event) {
	s.Events = slices.DeleteFunc(s.Events, func(x Event) bool { return x.ID == e.ID })
	s.Events = append(s.Events, e)
}

// Find is an event by its id.
func (s *Section) Find(id string) (Event, bool) {
	for _, e := range s.Events {
		if e.ID == id {
			return e, true
		}
	}
	return Event{}, false
}

// Meta is an account's sync state in the copy.
type Meta struct {
	SyncToken string `json:"syncToken"`
	SyncedAt  int64  `json:"syncedAt"`
	Error     string `json:"error"`
}

// Cache is the local copy: every account's calendars and events, global ids.
type Cache struct {
	Version   int              `json:"version"`
	Accounts  map[string]*Meta `json:"accounts"`
	SyncedAt  int64            `json:"syncedAt"`
	Error     string           `json:"error"`
	Calendars []Calendar       `json:"calendars"`
	Events    []Event          `json:"events"`
	// The calendars the user turned on (true) or off, by global id.
	Shown map[string]bool `json:"shown,omitempty"`
}

// Provider is one account's calendars at its provider.
type Provider interface {
	// Sync brings the provider's changes into the section: how many events
	// changed, and whether it fetched everything.
	Sync(sec *Section, full bool) (changed int, fetchedAll bool, err error)
	// Apply runs one change (ops: create, update, delete) with the
	// provider's own ids, updating the section.
	Apply(sec *Section, op map[string]any) (any, error)
}

// Factory makes an account's provider.
type Factory func(registry.Account) (Provider, error)

type entry struct {
	factory Factory
	has     func(registry.Account) bool
}

var factories = map[string]entry{}

// Register makes a provider kind available (its package's init); has, when
// given, says whether an account of that kind has calendars at all.
func Register(provider string, f Factory, has func(registry.Account) bool) {
	factories[provider] = entry{f, has}
}

// Supported says whether the account has calendars here.
func Supported(a registry.Account) bool {
	e, ok := factories[a.Provider]
	return ok && (e.has == nil || e.has(a))
}

func providerFor(a registry.Account) (Provider, error) {
	if !Supported(a) {
		return nil, core.Errorf("%s has no calendars here", a.Name)
	}
	return factories[a.Provider].factory(a)
}

// Load is the local copy (empty when there is none yet).
func Load() *Cache {
	c := &Cache{}
	if !core.ReadJSON(CacheFile, c) {
		c = &Cache{}
	}
	c.Version = 1
	if c.Accounts == nil {
		c.Accounts = map[string]*Meta{}
	}
	if c.Calendars == nil {
		c.Calendars = []Calendar{}
	}
	if c.Events == nil {
		c.Events = []Event{}
	}
	withLocal(c)
	return c
}

// withLocal reads the local account into the copy when it isn't there yet
// (a first run): its data needs no sync to show.
func withLocal(c *Cache) {
	if _, ok := c.Accounts[registry.Local.ID]; ok {
		return
	}
	p, err := providerFor(registry.Local)
	if err != nil {
		return
	}
	s := section(c, registry.Local.ID)
	if _, _, err := p.Sync(s, true); err == nil {
		put(c, registry.Local.ID, s)
	}
}

func save(c *Cache) error {
	accountOrder := map[string]int{}
	c.SyncedAt, c.Error = 0, ""
	for i, a := range registry.List() {
		accountOrder[a.ID] = i
		m := c.Accounts[a.ID]
		if m == nil || !Supported(a) {
			continue
		}
		if c.SyncedAt == 0 || m.SyncedAt < c.SyncedAt {
			c.SyncedAt = m.SyncedAt
		}
		if c.Error == "" && m.Error != "" {
			c.Error = a.Name + ": " + m.Error
		}
	}
	slices.SortStableFunc(c.Calendars, func(a, b Calendar) int {
		if accountOrder[a.Account] != accountOrder[b.Account] {
			return accountOrder[a.Account] - accountOrder[b.Account]
		}
		return a.Order - b.Order
	})
	slices.SortStableFunc(c.Events, func(a, b Event) int { return strings.Compare(a.Start, b.Start) })
	return core.WriteJSON(CacheFile, c)
}

func section(c *Cache, account string) *Section {
	m := c.Accounts[account]
	if m == nil {
		m = &Meta{}
	}
	s := &Section{
		SyncToken: m.SyncToken, SyncedAt: m.SyncedAt, Error: m.Error, Calendars: []Calendar{}, Events: []Event{},
		Shown: map[string]bool{},
	}
	for id, v := range c.Shown {
		if l := registry.LocalID(account, id); l != "" {
			s.Shown[l] = v
		}
	}
	for _, cal := range c.Calendars {
		if cal.Account == account {
			cal.ID = registry.LocalID(account, cal.ID)
			s.Calendars = append(s.Calendars, cal)
		}
	}
	for _, e := range c.Events {
		if e.Account == account {
			e.ID, e.CalendarID, e.RecurringID = registry.LocalID(account, e.ID), registry.LocalID(account, e.CalendarID), registry.LocalID(account, e.RecurringID)
			s.Events = append(s.Events, e)
		}
	}
	return s
}

func globalEvent(account string, e Event) Event {
	e.Account = account
	e.ID = registry.GlobalID(account, e.ID)
	e.CalendarID = registry.GlobalID(account, e.CalendarID)
	e.RecurringID = registry.GlobalID(account, e.RecurringID)
	return e
}

func put(c *Cache, account string, s *Section) {
	c.Accounts[account] = &Meta{SyncToken: s.SyncToken, SyncedAt: s.SyncedAt, Error: s.Error}
	c.Calendars = slices.DeleteFunc(c.Calendars, func(x Calendar) bool { return x.Account == account })
	for _, cal := range s.Calendars {
		cal.ID, cal.Account = registry.GlobalID(account, cal.ID), account
		if cal.DefaultReminders == nil {
			cal.DefaultReminders = []int{}
		}
		if v, ok := c.Shown[cal.ID]; ok {
			cal.Hidden = !v
		}
		c.Calendars = append(c.Calendars, cal)
	}
	c.Events = slices.DeleteFunc(c.Events, func(e Event) bool { return e.Account == account })
	for _, e := range s.Events {
		c.Events = append(c.Events, globalEvent(account, e))
	}
}

// Forget drops an account's calendars from the copy; every account's with "".
func Forget(account string) error {
	unlock, err := core.Lock("calendar")
	if err != nil {
		return err
	}
	defer unlock()
	c := Load()
	if account == "" {
		c = &Cache{Accounts: map[string]*Meta{}, Calendars: []Calendar{}, Events: []Event{}}
	} else {
		put(c, account, &Section{})
		delete(c.Accounts, account)
	}
	return save(c)
}

// -- sync ------------------------------------------------------------------

// AccountSync is what a sync did for one account.
type AccountSync struct {
	Account   string `json:"account"`
	Full      bool   `json:"full"`
	Changed   int    `json:"changed"`
	Calendars int    `json:"calendars"`
	Count     int    `json:"count"`
	Error     string `json:"error,omitempty"`
}

// SyncResult is what a sync did.
type SyncResult struct {
	Accounts  []AccountSync `json:"accounts"`
	Calendars int           `json:"calendars"`
	Count     int           `json:"count"`
	SyncedAt  int64         `json:"syncedAt"`
}

// Sync brings each account's changes into the copy (one account's with
// account set). A failing account keeps its events and its failure in the
// copy; it fails only when every account did.
func Sync(account string, full bool) (*SyncResult, error) {
	accounts := []registry.Account{}
	if account != "" {
		a, err := registry.Get(account)
		if err != nil {
			return nil, err
		}
		accounts = append(accounts, a)
	} else {
		for _, a := range registry.List() {
			if Supported(a) {
				accounts = append(accounts, a)
			}
		}
		if len(accounts) == 0 {
			return nil, core.AuthErrorf("no account with calendars connected")
		}
	}
	unlock, err := core.Lock("calendar")
	if err != nil {
		return nil, err
	}
	defer unlock()
	c := Load()
	res := &SyncResult{Accounts: []AccountSync{}}
	var firstErr error
	failed := 0
	for _, a := range accounts {
		s := section(c, a.ID)
		r := AccountSync{Account: a.ID}
		p, err := providerFor(a)
		if err == nil {
			r.Changed, r.Full, err = p.Sync(s, full)
		}
		if err != nil {
			s.Error, r.Error = err.Error(), err.Error()
			failed++
			if firstErr == nil {
				firstErr = err
			}
		} else {
			s.Error = ""
		}
		r.Calendars, r.Count = len(s.Calendars), len(s.Events)
		put(c, a.ID, s)
		res.Accounts = append(res.Accounts, r)
	}
	if err := save(c); err != nil {
		return nil, err
	}
	res.Calendars, res.Count, res.SyncedAt = len(c.Calendars), len(c.Events), c.SyncedAt
	if failed == len(accounts) {
		return res, firstErr
	}
	return res, nil
}

// -- changes ---------------------------------------------------------------

// Ops are the changes apply takes, as {"op": …} (or "action").
var Ops = []string{"create", "update", "delete", "show_calendar", "hide_calendar"}

// Result is one change's outcome.
type Result = core.Result

// Apply runs {op…} or {ops: […]}, in order, each on its own, each at its
// account's provider.
func Apply(request any) ([]Result, error) {
	ops, err := core.Ops(request, MaxOps)
	if err != nil {
		return nil, err
	}
	unlock, err := core.Lock("calendar")
	if err != nil {
		return nil, err
	}
	defer unlock()
	c := Load()
	results, authErr := core.RunOps(ops, func(op map[string]any) (any, error) { return apply(c, op) })
	if err := save(c); err != nil {
		return nil, err
	}
	// Every change refused for want of a sign-in: say so (exit 2).
	if authErr != nil {
		return nil, authErr
	}
	return results, nil
}

// findCalendar is a calendar by global id or name (a name in two accounts
// must be given by id); "" is the first writable one (an account's primary
// first).
func findCalendar(c *Cache, want string) (Calendar, error) {
	want = strings.TrimSpace(want)
	if want == "" {
		// The accounts in their order (the local one last), each one's
		// primary first; shown calendars before hidden ones.
		for _, hidden := range []bool{false, true} {
			for _, a := range registry.List() {
				for _, primary := range []bool{true, false} {
					for _, cal := range c.Calendars {
						if cal.Account == a.ID && !cal.ReadOnly && cal.Primary == primary && cal.Hidden == hidden {
							return cal, nil
						}
					}
				}
			}
		}
		return Calendar{}, core.Errorf("no calendar to write in")
	}
	found := []Calendar{}
	for _, cal := range c.Calendars {
		if cal.ID == want {
			return cal, nil
		}
		if strings.EqualFold(cal.Name, want) {
			found = append(found, cal)
		}
	}
	names := []string{}
	for _, cal := range c.Calendars {
		names = append(names, cal.Name)
	}
	switch {
	case len(found) == 1:
		return found[0], nil
	case len(found) > 1:
		return Calendar{}, core.Errorf("'%s' is a calendar in several accounts: give its id", want)
	}
	return Calendar{}, core.Errorf("no calendar '%s': %s", want, strings.Join(names, ", "))
}

func apply(c *Cache, op map[string]any) (any, error) {
	kind := core.Kind(op)
	if !slices.Contains(Ops, kind) {
		return nil, core.Errorf("unknown op '%s': %s", kind, strings.Join(Ops, ", "))
	}
	op = core.Clone(op)
	// Shown or not: the user's choice, kept in the copy (Google's own
	// selection left as it is); a calendar turned on gets its events with
	// the next sync.
	if kind == "show_calendar" || kind == "hide_calendar" {
		want, _ := op["calendar"].(string)
		if strings.TrimSpace(want) == "" {
			return nil, core.Errorf("`calendar` is required (a calendar's id or name)")
		}
		cal, err := findCalendar(c, want)
		if err != nil {
			return nil, err
		}
		if c.Shown == nil {
			c.Shown = map[string]bool{}
		}
		c.Shown[cal.ID] = kind == "show_calendar"
		for i := range c.Calendars {
			if c.Calendars[i].ID == cal.ID {
				c.Calendars[i].Hidden = kind == "hide_calendar"
				cal = c.Calendars[i]
			}
		}
		return cal, nil
	}
	var account string
	if kind == "create" {
		want, _ := op["calendar"].(string)
		cal, err := findCalendar(c, want)
		if err != nil {
			return nil, err
		}
		if cal.ReadOnly {
			return nil, core.Errorf("'%s' is read-only", cal.Name)
		}
		account, op["calendar"] = cal.Account, registry.LocalID(cal.Account, cal.ID)
	} else {
		want, _ := op["id"].(string)
		if strings.TrimSpace(want) == "" {
			return nil, core.Errorf("`id` is required (an event's id from events)")
		}
		e, ok := findEvent(c, want)
		if !ok {
			return nil, core.Errorf("no event '%s' (list or sync first)", want)
		}
		account, op["id"] = e.Account, registry.LocalID(e.Account, e.ID)
		// The whole series changed from one of its occurrences ("all"): its
		// times move as that occurrence's did.
		if all, _ := op["all"].(bool); all {
			if err := seriesTimes(e, op); err != nil {
				return nil, err
			}
		}
		if cal, ok := calendarOf(c, e.CalendarID); ok && cal.ReadOnly {
			return nil, core.Errorf("'%s' is read-only", cal.Name)
		}
		if to, _ := op["calendar"].(string); to != "" {
			cal, err := findCalendar(c, to)
			if err != nil {
				return nil, err
			}
			if cal.Account != account {
				return nil, core.Errorf("events move between calendars of the same account only")
			}
			op["calendar"] = registry.LocalID(account, cal.ID)
		}
	}
	a, err := registry.Get(account)
	if err != nil {
		return nil, err
	}
	p, err := providerFor(a)
	if err != nil {
		return nil, err
	}
	s := section(c, account)
	res, err := p.Apply(s, op)
	put(c, account, s)
	if err != nil {
		return nil, err
	}
	switch r := res.(type) {
	case Event:
		return globalEvent(account, r), nil
	case map[string]any:
		if id, ok := r["deleted"].(string); ok {
			r["deleted"] = registry.GlobalID(account, id)
		}
		return r, nil
	}
	return res, nil
}

// seriesTimes turns an occurrence's new start and end (op's, with its
// original start in "occurrence") into the series' own: shifted alike.
func seriesTimes(series Event, op map[string]any) error {
	occ, _ := op["occurrence"].(string)
	delete(op, "occurrence")
	delete(op, "all")
	start, hasStart := op["start"].(string)
	if !hasStart || occ == "" {
		return nil
	}
	end, _ := op["end"].(string)
	was, err := ParseTime(occ)
	if err != nil {
		return core.Errorf("`occurrence` must be the occurrence's start, as events gives it")
	}
	now, nowDate, err := InputTime(start)
	if err != nil {
		return err
	}
	first, _, ok := span(series)
	if !ok {
		return core.Errorf("the series' start can't be read")
	}
	allDay, given := op["allDay"].(bool)
	if !given {
		allDay = nowDate
	}
	layout := "2006-01-02T15:04"
	if allDay {
		layout = "2006-01-02"
	}
	shift := now.Sub(was)
	if allDay || series.AllDay {
		// Whole days.
		shift = time.Duration(int(now.Sub(time.Date(was.Year(), was.Month(), was.Day(), 0, 0, 0, 0, time.Local)).Hours()/24)) * 24 * time.Hour
	}
	newFirst := first.Add(shift)
	if !allDay && series.AllDay {
		// An all-day series given hours: its first day at that time.
		newFirst = time.Date(first.Year(), first.Month(), first.Day(), now.Hour(), now.Minute(), 0, 0, time.Local)
	}
	op["start"] = newFirst.In(time.Local).Format(layout)
	if end != "" {
		e, _, err := InputTime(end)
		if err != nil {
			return err
		}
		length := e.Sub(now)
		if allDay {
			length = e.Sub(time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.Local))
		}
		op["end"] = newFirst.Add(length).In(time.Local).Format(layout)
	}
	return nil
}

func findEvent(c *Cache, id string) (Event, bool) {
	for _, e := range c.Events {
		if e.ID == id {
			return e, true
		}
	}
	return Event{}, false
}

func calendarOf(c *Cache, id string) (Calendar, bool) {
	for _, cal := range c.Calendars {
		if cal.ID == id {
			return cal, true
		}
	}
	return Calendar{}, false
}

// Summary is the calendar part of status, from the copy (Load).
func (c *Cache) Summary() map[string]any {
	path, _ := core.StatePath(CacheFile)
	return map[string]any{"calendars": len(c.Calendars), "count": len(c.Events), "syncedAt": c.SyncedAt, "error": c.Error, "cache": path}
}

// AccountError is the account's last calendar sync failure.
func (c *Cache) AccountError(account string) string {
	if m := c.Accounts[account]; m != nil {
		return m.Error
	}
	return ""
}

// ParseTime is an event time: RFC 3339, or a date (local midnight).
func ParseTime(v string) (time.Time, error) {
	if len(v) == 10 {
		return time.ParseInLocation("2006-01-02", v, time.Local)
	}
	return time.Parse(time.RFC3339, v)
}
