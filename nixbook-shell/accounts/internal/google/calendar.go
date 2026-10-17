package google

import (
	"encoding/json"
	"errors"
	"net/url"
	"slices"
	"time"

	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/calendar"
	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/core"
	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/registry"
)

func calendarAPI() string {
	return core.Endpoint("NIXBOOK_ACCOUNTS_GOOGLE_CALENDAR_API", "https://www.googleapis.com/calendar/v3")
}

func init() {
	calendar.Register("google", func(a registry.Account) (calendar.Provider, error) {
		return &googleCalendar{account: a}, nil
	}, nil)
}

// Past events older than this aren't kept (a series is, while it repeats).
const keepPast = 400 * 24 * time.Hour

// googleCalendar is a Google account's calendars (the ones shown in Google
// Calendar), each synced with its sync token; series kept whole, with
// their changed and cancelled occurrences.
type googleCalendar struct {
	account registry.Account
	token   string
}

func (g *googleCalendar) call(method, path string, body any, out any) error {
	if g.token == "" {
		t, err := AccessToken(g.account)
		if err != nil {
			return err
		}
		g.token = t
	}
	return core.Call(method, calendarAPI()+path, body, nil, g.token, out)
}

func (g *googleCalendar) calendars() ([]calendar.Calendar, error) {
	out, page := []calendar.Calendar{}, ""
	for {
		q := url.Values{"maxResults": {"250"}}
		if page != "" {
			q.Set("pageToken", page)
		}
		var r struct {
			Items []obj  `json:"items"`
			Next  string `json:"nextPageToken"`
		}
		if err := g.call("GET", "/users/me/calendarList?"+q.Encode(), nil, &r); err != nil {
			return nil, err
		}
		for _, c := range r.Items {
			if hidden, _ := c["hidden"].(bool); hidden {
				continue
			}
			if selected, ok := c["selected"].(bool); ok && !selected {
				continue
			}
			name := str(c, "summaryOverride")
			if name == "" {
				name = str(c, "summary")
			}
			primary, _ := c["primary"].(bool)
			role := str(c, "accessRole")
			reminders := []int{}
			for _, r := range list(c, "defaultReminders") {
				if str(r, "method") == "popup" {
					reminders = append(reminders, num(r, "minutes"))
				}
			}
			out = append(out, calendar.Calendar{
				ID: str(c, "id"), Name: name, Color: str(c, "backgroundColor"), Primary: primary,
				ReadOnly: role != "owner" && role != "writer", Order: len(out), DefaultReminders: reminders,
			})
		}
		if page = r.Next; page == "" {
			return out, nil
		}
	}
}

// eventTime is Google's {date} or {dateTime, timeZone}.
func eventTime(o obj) (string, bool, string) {
	if d := str(o, "date"); d != "" {
		return d, true, ""
	}
	return str(o, "dateTime"), false, str(o, "timeZone")
}

func fromGoogleEvent(calendarID string, e obj) calendar.Event {
	start, allDay, tz := eventTime(objOf(e, "start"))
	end, _, _ := eventTime(objOf(e, "end"))
	ev := calendar.Event{
		ID: str(e, "id"), CalendarID: calendarID, Summary: str(e, "summary"), Description: str(e, "description"),
		Location: str(e, "location"), Start: start, End: end, AllDay: allDay, TimeZone: tz,
		RecurringID: str(e, "recurringEventId"), Cancelled: str(e, "status") == "cancelled", Updated: str(e, "updated"),
	}
	if ev.RecurringID != "" {
		ev.OriginalStart, _, _ = eventTime(objOf(e, "originalStartTime"))
	}
	lines, _ := e["recurrence"].([]any)
	for _, r := range lines {
		if s, ok := r.(string); ok {
			ev.Recurrence = append(ev.Recurrence, s)
		}
	}
	ev.MeetingURL = str(e, "hangoutLink")
	for _, ep := range list(objOf(e, "conferenceData"), "entryPoints") {
		if ev.MeetingURL == "" && str(ep, "entryPointType") == "video" {
			ev.MeetingURL = str(ep, "uri")
		}
	}
	if ev.MeetingURL == "" {
		ev.MeetingURL = calendar.MeetingURL(ev.Location, ev.Description)
	}
	rem := objOf(e, "reminders")
	if useDefault, _ := rem["useDefault"].(bool); !useDefault && rem != nil {
		ev.Reminders = []int{}
		for _, o := range list(rem, "overrides") {
			if str(o, "method") == "popup" {
				ev.Reminders = append(ev.Reminders, num(o, "minutes"))
			}
		}
	}
	return ev
}

func objOf(o obj, key string) obj {
	v, _ := o[key].(obj)
	return v
}

// stale: ended long ago and not repeating.
func stale(e calendar.Event) bool {
	if len(e.Recurrence) > 0 {
		return false
	}
	end, err := calendar.ParseTime(e.End)
	return err == nil && end.Before(time.Now().Add(-keepPast))
}

func (g *googleCalendar) events(calendarID, syncToken string) ([]obj, string, error) {
	out, page, next := []obj{}, "", ""
	for {
		q := url.Values{"maxResults": {"2500"}, "showDeleted": {"true"}, "singleEvents": {"false"}}
		if syncToken != "" {
			q.Set("syncToken", syncToken)
		}
		if page != "" {
			q.Set("pageToken", page)
		}
		var r struct {
			Items []obj  `json:"items"`
			Next  string `json:"nextPageToken"`
			Sync  string `json:"nextSyncToken"`
		}
		if err := g.call("GET", "/calendars/"+url.PathEscape(calendarID)+"/events?"+q.Encode(), nil, &r); err != nil {
			return nil, "", err
		}
		out = append(out, r.Items...)
		if r.Sync != "" {
			next = r.Sync
		}
		if page = r.Next; page == "" {
			return out, next, nil
		}
	}
}

// Sync: each calendar's changes since its sync token (Google drops a token
// after a while: then everything again), everything for a new calendar.
func (g *googleCalendar) Sync(sec *calendar.Section, full bool) (int, bool, error) {
	cals, err := g.calendars()
	if err != nil {
		return 0, false, err
	}
	tokens := map[string]string{}
	_ = json.Unmarshal([]byte(sec.SyncToken), &tokens)
	newTokens := map[string]string{}
	byCal := map[string][]calendar.Event{}
	for _, e := range sec.Events {
		byCal[e.CalendarID] = append(byCal[e.CalendarID], e)
	}
	all, changed, fetchedAll := []calendar.Event{}, 0, true
	for _, cal := range cals {
		current := map[string]calendar.Event{}
		token := ""
		if !full {
			token = tokens[cal.ID]
		}
		items, next, err := g.events(cal.ID, token)
		var api *core.APIError
		if err != nil && token != "" && errors.As(err, &api) && api.Status == 410 {
			token = ""
			items, next, err = g.events(cal.ID, "")
		}
		if err != nil {
			return 0, false, err
		}
		if token != "" {
			fetchedAll = false
			for _, e := range byCal[cal.ID] {
				current[e.ID] = e
			}
		}
		for _, item := range items {
			e := fromGoogleEvent(cal.ID, item)
			// A cancelled event alone is gone; a cancelled occurrence stays,
			// so its series skips it.
			if e.Cancelled && e.RecurringID == "" {
				if _, ok := current[e.ID]; ok {
					delete(current, e.ID)
					changed++
				}
				continue
			}
			if stale(e) {
				delete(current, e.ID)
				continue
			}
			current[e.ID] = e
			changed++
		}
		newTokens[cal.ID] = next
		for _, e := range current {
			all = append(all, e)
		}
	}
	data, _ := json.Marshal(newTokens)
	sec.SyncToken = string(data)
	sec.Calendars, sec.Events = cals, all
	sec.SyncedAt = time.Now().UnixMilli()
	return changed, fetchedAll, nil
}

// -- changes ---------------------------------------------------------------

func googleTime(t time.Time, allDay bool, tz string) obj {
	if allDay {
		return obj{"date": t.Format("2006-01-02")}
	}
	o := obj{"dateTime": t.Format(time.RFC3339)}
	if tz != "" {
		o["timeZone"] = tz
	}
	return o
}

// body is the Google event fields for those given.
func body(f calendar.Fields, recurring bool) obj {
	b := obj{}
	if f.Summary != nil {
		b["summary"] = *f.Summary
	}
	if f.Description != nil {
		b["description"] = *f.Description
	}
	if f.Location != nil {
		b["location"] = *f.Location
	}
	if f.HasTime {
		tz := f.TimeZone
		if tz == "" && (recurring || f.HasRecurrence && len(f.Recurrence) > 0) {
			// A series repeats in a zone (Google needs one).
			tz = calendar.LocalZone()
		}
		b["start"], b["end"] = googleTime(f.Start, f.AllDay, tz), googleTime(f.End, f.AllDay, tz)
	}
	if f.HasReminders {
		if f.DefaultReminders {
			b["reminders"] = obj{"useDefault": true}
		} else {
			overrides := []obj{}
			for _, m := range f.Reminders {
				overrides = append(overrides, obj{"method": "popup", "minutes": m})
			}
			b["reminders"] = obj{"useDefault": false, "overrides": overrides}
		}
	}
	if f.HasRecurrence {
		b["recurrence"] = f.Recurrence
	}
	return b
}

// instanceID is Google's id of a series' occurrence (its original start).
func instanceID(master, occurrence string) (string, error) {
	t, err := calendar.ParseTime(occurrence)
	if err != nil {
		return "", core.Errorf("`occurrence` must be the occurrence's start, as events gives it")
	}
	if len(occurrence) == 10 {
		return master + "_" + t.Format("20060102"), nil
	}
	return master + "_" + t.UTC().Format("20060102T150405Z"), nil
}

// Apply runs one change on Google, its answer put in the section.
func (g *googleCalendar) Apply(sec *calendar.Section, op obj) (any, error) {
	kind := str(op, "op")
	if kind == "" {
		kind = str(op, "action")
	}
	fields, err := calendar.ParseFields(op, kind == "create")
	if err != nil && kind != "delete" {
		return nil, err
	}
	if kind == "create" {
		cal := str(op, "calendar")
		var r obj
		if err := g.call("POST", "/calendars/"+url.PathEscape(cal)+"/events", body(fields, false), &r); err != nil {
			return nil, err
		}
		e := fromGoogleEvent(cal, r)
		sec.Upsert(e)
		return e, nil
	}
	e, ok := sec.Find(str(op, "id"))
	if !ok {
		return nil, core.Errorf("no event '%s' (sync first)", str(op, "id"))
	}
	id := e.ID
	if e.RecurringID != "" {
		// A changed occurrence: itself.
		id = e.ID
	} else if occ := str(op, "occurrence"); occ != "" {
		if len(e.Recurrence) == 0 {
			return nil, core.Errorf("'%s' isn't a recurring event", e.Summary)
		}
		if id, err = instanceID(e.ID, occ); err != nil {
			return nil, err
		}
	}
	path := "/calendars/" + url.PathEscape(e.CalendarID) + "/events/" + url.PathEscape(id)
	switch kind {
	case "delete":
		if err := g.call("DELETE", path, nil, nil); err != nil {
			return nil, err
		}
		if id == e.ID && e.RecurringID == "" {
			// The series (or the event) and its occurrences.
			sec.Events = slices.DeleteFunc(sec.Events, func(x calendar.Event) bool { return x.ID == e.ID || x.RecurringID == e.ID })
		} else {
			// One occurrence: cancelled, the series skips it.
			cancelled := calendar.Event{
				ID: id, CalendarID: e.CalendarID, RecurringID: firstNonEmpty(e.RecurringID, e.ID),
				OriginalStart: firstNonEmpty(e.OriginalStart, str(op, "occurrence")), Cancelled: true, Start: e.Start, End: e.End, AllDay: e.AllDay,
			}
			sec.Upsert(cancelled)
		}
		return obj{"deleted": e.ID, "summary": e.Summary}, nil
	case "update":
		b := body(fields, len(e.Recurrence) > 0)
		to := str(op, "calendar")
		if len(b) == 0 && (to == "" || to == e.CalendarID) {
			return nil, core.Errorf("nothing to change: give the fields to set")
		}
		var r obj
		if len(b) > 0 {
			if err := g.call("PATCH", path, b, &r); err != nil {
				return nil, err
			}
		}
		calID := e.CalendarID
		if to != "" && to != e.CalendarID {
			q := url.Values{"destination": {to}}
			if err := g.call("POST", path+"/move?"+q.Encode(), nil, &r); err != nil {
				return nil, err
			}
			calID = to
		}
		updated := fromGoogleEvent(calID, r)
		sec.Upsert(updated)
		if calID != e.CalendarID {
			for i := range sec.Events {
				if sec.Events[i].RecurringID == e.ID {
					sec.Events[i].CalendarID = calID
				}
			}
		}
		return updated, nil
	}
	return nil, core.Errorf("unknown op '%s'", kind)
}

func firstNonEmpty(v ...string) string {
	for _, s := range v {
		if s != "" {
			return s
		}
	}
	return ""
}
