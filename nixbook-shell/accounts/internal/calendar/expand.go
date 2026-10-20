package calendar

import (
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/teambition/rrule-go"
)

// Occurrence is one event happening: a single event, one occurrence of a
// series, or a changed occurrence.
type Occurrence struct {
	// The event to change (the series for an occurrence of it) and, for an
	// occurrence of a series, its original start (to change or delete that
	// occurrence alone).
	ID         string `json:"id"`
	Occurrence string `json:"occurrence,omitempty"`
	Recurring  bool   `json:"recurring"`
	Account    string `json:"account"`
	CalendarID string `json:"calendarId"`
	Calendar   string `json:"calendar"`
	Color      string `json:"color"`
	ReadOnly   bool   `json:"readOnly"`
	Summary    string `json:"summary"`
	Desc       string `json:"description"`
	Location   string `json:"location"`
	MeetingURL string `json:"meetingUrl"`
	// RFC 3339 in local time, or YYYY-MM-DD (End exclusive) all-day.
	Start  string `json:"start"`
	End    string `json:"end"`
	AllDay bool   `json:"allDay"`
	// Minutes before (the event's, else its calendar's).
	Reminders []int `json:"reminders"`
}

// maxOccurrences caps a series' expansion in one range.
const maxOccurrences = 1000

func format(t time.Time, allDay bool) string {
	if allDay {
		return t.Format("2006-01-02")
	}
	return t.In(time.Local).Format(time.RFC3339)
}

// span is an event's start and end.
func span(e Event) (time.Time, time.Time, bool) {
	start, err := ParseTime(e.Start)
	if err != nil {
		return time.Time{}, time.Time{}, false
	}
	end, err := ParseTime(e.End)
	if err != nil || !end.After(start) {
		if e.AllDay {
			end = start.AddDate(0, 0, 1)
		} else {
			end = start
		}
	}
	return start, end, true
}

// zones are the IANA zones loaded so far: time.LoadLocation reads the zone
// file each time, and many series share a zone.
var zones sync.Map

func zone(name string) (*time.Location, bool) {
	if l, ok := zones.Load(name); ok {
		return l.(*time.Location), true
	}
	l, err := time.LoadLocation(name)
	if err != nil {
		return nil, false
	}
	zones.Store(name, l)
	return l, true
}

// recurrenceSet is a series' occurrences' starts, in its own zone.
func recurrenceSet(e Event, start time.Time) (*rrule.Set, error) {
	loc := time.Local
	if e.TimeZone != "" && !e.AllDay {
		if l, ok := zone(e.TimeZone); ok {
			loc = l
		}
	}
	first := "DTSTART:" + start.In(loc).Format("20060102T150405")
	if loc != time.Local {
		first = "DTSTART;TZID=" + loc.String() + ":" + start.In(loc).Format("20060102T150405")
	} else if e.AllDay {
		first = "DTSTART:" + start.Format("20060102T150405")
	}
	lines := []string{first}
	for _, l := range e.Recurrence {
		l = strings.TrimSpace(l)
		up := strings.ToUpper(l)
		if strings.HasPrefix(up, "RRULE") || strings.HasPrefix(up, "EXDATE") || strings.HasPrefix(up, "RDATE") {
			// All-day dates as midnight of that day.
			lines = append(lines, strings.Replace(l, ";VALUE=DATE:", ":", 1))
		}
	}
	return rrule.StrSliceToRRuleSetInLoc(lines, loc)
}

// between is the set's starts from after to before (both included), at
// most maxOccurrences: stops there rather than expanding all of them.
func between(set *rrule.Set, after, before time.Time) []time.Time {
	out := []time.Time{}
	next := set.Iterator()
	for len(out) < maxOccurrences {
		t, ok := next()
		if !ok || t.After(before) {
			break
		}
		if !t.Before(after) {
			out = append(out, t)
		}
	}
	return out
}

// sameStart says whether an override's original start is that occurrence.
func sameStart(original string, t time.Time, allDay bool) bool {
	o, err := ParseTime(original)
	if err != nil {
		return false
	}
	if allDay || len(original) == 10 {
		return o.Format("2006-01-02") == t.Format("2006-01-02")
	}
	return o.Equal(t)
}

// Occurrences are the events happening between from and to (overlapping),
// series expanded, sorted by start; only those calendars' when calendars
// is given, else the shown calendars'.
func Occurrences(from, to time.Time, calendars []string) []Occurrence {
	return Load().Occurrences(from, to, calendars)
}

// Occurrences is Occurrences from this copy.
func (c *Cache) Occurrences(from, to time.Time, calendars []string) []Occurrence {
	cals := map[string]Calendar{}
	for _, cal := range c.Calendars {
		cals[cal.ID] = cal
	}
	overrides := map[string][]Event{}
	for _, e := range c.Events {
		if e.RecurringID != "" {
			overrides[e.RecurringID] = append(overrides[e.RecurringID], e)
		}
	}
	out := []Occurrence{}
	// Each occurrence's sort key (its start in UTC), made once.
	keys := []string{}
	add := func(e Event, id, occurrence string, recurring bool, start, end time.Time) {
		if !end.After(from) || !start.Before(to) {
			return
		}
		cal := cals[e.CalendarID]
		if len(calendars) > 0 && !slices.Contains(calendars, e.CalendarID) || len(calendars) == 0 && cal.Hidden {
			return
		}
		reminders := e.Reminders
		if reminders == nil {
			reminders = cal.DefaultReminders
		}
		if reminders == nil {
			reminders = []int{}
		}
		out = append(out, Occurrence{
			ID: id, Occurrence: occurrence, Recurring: recurring, Account: e.Account, CalendarID: e.CalendarID,
			Calendar: cal.Name, Color: cal.Color, ReadOnly: cal.ReadOnly, Summary: e.Summary, Desc: e.Description,
			Location: e.Location, MeetingURL: e.MeetingURL, Start: format(start, e.AllDay), End: format(end, e.AllDay),
			AllDay: e.AllDay, Reminders: reminders,
		})
		keys = append(keys, sortKey(out[len(out)-1]))
	}
	for _, e := range c.Events {
		if e.Cancelled {
			continue
		}
		start, end, ok := span(e)
		if !ok {
			continue
		}
		if e.RecurringID != "" {
			// A changed occurrence: changed or deleted, it stands for its
			// series' occurrence.
			add(e, e.RecurringID, e.OriginalStart, true, start, end)
			continue
		}
		if len(e.Recurrence) == 0 {
			add(e, e.ID, "", false, start, end)
			continue
		}
		set, err := recurrenceSet(e, start)
		if err != nil {
			// A rule this can't read: the first occurrence at least.
			add(e, e.ID, "", false, start, end)
			continue
		}
		length := end.Sub(start)
		days := int(length.Hours()/24 + 0.5)
		for _, s := range between(set, from.Add(-length), to) {
			if e.AllDay {
				s = time.Date(s.Year(), s.Month(), s.Day(), 0, 0, 0, 0, time.Local)
			}
			if slices.ContainsFunc(overrides[e.ID], func(o Event) bool { return sameStart(o.OriginalStart, s, e.AllDay) }) {
				continue
			}
			finish := s.Add(length)
			if e.AllDay {
				finish = s.AddDate(0, 0, days)
			}
			add(e, e.ID, format(s, e.AllDay), true, s, finish)
		}
	}
	order := make([]int, len(out))
	for i := range order {
		order[i] = i
	}
	slices.SortStableFunc(order, func(i, j int) int {
		a, b := out[i], out[j]
		if a.AllDay != b.AllDay && a.Start[:10] == b.Start[:10] {
			if a.AllDay {
				return -1
			}
			return 1
		}
		return strings.Compare(keys[i], keys[j])
	})
	sorted := make([]Occurrence, len(out))
	for i, j := range order {
		sorted[i] = out[j]
	}
	return sorted
}

func sortKey(o Occurrence) string {
	if t, err := ParseTime(o.Start); err == nil {
		return t.UTC().Format(time.RFC3339)
	}
	return o.Start
}
