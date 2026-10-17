package calendar

import (
	"strings"
	"testing"
	"time"

	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/core"
)

// withCopy runs f with a local copy holding those calendars and events,
// in Europe/Paris.
func withCopy(t *testing.T, cals []Calendar, events []Event, f func()) {
	t.Helper()
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	paris, err := time.LoadLocation("Europe/Paris")
	if err != nil {
		t.Skip("no time zone database")
	}
	old := time.Local
	time.Local = paris
	defer func() { time.Local = old }()
	if err := core.WriteJSON(CacheFile, &Cache{Calendars: cals, Events: events}); err != nil {
		t.Fatal(err)
	}
	f()
}

func starts(occ []Occurrence) string {
	out := []string{}
	for _, o := range occ {
		out = append(out, o.Start)
	}
	return strings.Join(out, " ")
}

func day(s string) time.Time {
	t, _ := time.ParseInLocation("2006-01-02", s, time.Local)
	return t
}

func TestWeeklySeriesAcrossDST(t *testing.T) {
	withCopy(t, []Calendar{{ID: "a:c", Name: "Work", DefaultReminders: []int{10}}}, []Event{{
		ID: "a:standup", CalendarID: "a:c", Summary: "Standup", TimeZone: "Europe/Paris",
		Start: "2026-10-19T09:30:00+02:00", End: "2026-10-19T09:45:00+02:00",
		Recurrence: []string{"RRULE:FREQ=WEEKLY;COUNT=4"},
	}}, func() {
		got := Occurrences(day("2026-10-01"), day("2026-12-01"), nil)
		// Still 9:30 local after the switch to winter time (Oct 25).
		want := "2026-10-19T09:30:00+02:00 2026-10-26T09:30:00+01:00 2026-11-02T09:30:00+01:00 2026-11-09T09:30:00+01:00"
		if starts(got) != want {
			t.Fatalf("starts:\n got %s\nwant %s", starts(got), want)
		}
		if got[0].ID != "a:standup" || got[0].Occurrence != got[0].Start || !got[0].Recurring {
			t.Fatalf("occurrence identity: %+v", got[0])
		}
		if len(got[0].Reminders) != 1 || got[0].Reminders[0] != 10 || got[0].Calendar != "Work" {
			t.Fatalf("calendar defaults: %+v", got[0])
		}
	})
}

func TestExceptionsAndOverrides(t *testing.T) {
	withCopy(t, []Calendar{{ID: "a:c"}}, []Event{
		{
			ID: "a:s", CalendarID: "a:c", Summary: "Gym", TimeZone: "Europe/Paris",
			Start: "2026-11-02T18:00:00+01:00", End: "2026-11-02T19:00:00+01:00",
			Recurrence: []string{"RRULE:FREQ=DAILY;COUNT=5", "EXDATE;TZID=Europe/Paris:20261103T180000"},
			Reminders:  []int{},
		},
		// The 4th moved an hour later; the 5th cancelled.
		{
			ID: "a:s_4", CalendarID: "a:c", RecurringID: "a:s", OriginalStart: "2026-11-05T18:00:00+01:00",
			Summary: "Gym (late)", Start: "2026-11-05T19:00:00+01:00", End: "2026-11-05T20:00:00+01:00",
		},
		{ID: "a:s_5", CalendarID: "a:c", RecurringID: "a:s", OriginalStart: "2026-11-06T18:00:00+01:00", Cancelled: true},
	}, func() {
		got := Occurrences(day("2026-11-01"), day("2026-11-10"), nil)
		want := "2026-11-02T18:00:00+01:00 2026-11-04T18:00:00+01:00 2026-11-05T19:00:00+01:00"
		if starts(got) != want {
			t.Fatalf("starts:\n got %s\nwant %s", starts(got), want)
		}
		if got[2].Summary != "Gym (late)" || got[2].ID != "a:s" || got[2].Occurrence != "2026-11-05T18:00:00+01:00" {
			t.Fatalf("override: %+v", got[2])
		}
		if len(got[0].Reminders) != 0 {
			t.Fatalf("no reminders of its own: %+v", got[0].Reminders)
		}
	})
}

func TestAllDay(t *testing.T) {
	withCopy(t, []Calendar{{ID: "a:c"}}, []Event{
		{
			ID: "a:b", CalendarID: "a:c", Summary: "Birthday", AllDay: true, Start: "2026-03-10", End: "2026-03-11",
			Recurrence: []string{"RRULE:FREQ=YEARLY", "EXDATE;VALUE=DATE:20280310"},
		},
		{ID: "a:trip", CalendarID: "a:c", Summary: "Trip", AllDay: true, Start: "2026-11-02", End: "2026-11-05"},
		{ID: "a:m", CalendarID: "a:c", Summary: "Meeting", Start: "2026-11-03T09:00:00+01:00", End: "2026-11-03T10:00:00+01:00"},
	}, func() {
		got := Occurrences(day("2026-01-01"), day("2029-12-31"), nil)
		want := "2026-03-10 2026-11-02 2026-11-03T09:00:00+01:00 2027-03-10 2029-03-10"
		if starts(got) != want {
			t.Fatalf("starts:\n got %s\nwant %s", starts(got), want)
		}
		if got[1].End != "2026-11-05" {
			t.Fatalf("a 3-day event's end: %s", got[1].End)
		}
		// Overlapping the range is enough: the trip, from its 2nd day.
		if s := starts(Occurrences(day("2026-11-03"), day("2026-11-04"), nil)); s != "2026-11-02 2026-11-03T09:00:00+01:00" {
			t.Fatalf("overlap: %s", s)
		}
		if s := starts(Occurrences(day("2026-11-03"), day("2026-11-04"), []string{"a:other"})); s != "" {
			t.Fatalf("calendar filter: %s", s)
		}
	})
}

func TestParseFields(t *testing.T) {
	t.Setenv("TZ", "Europe/Paris")
	f, err := ParseFields(map[string]any{"summary": "Dentist", "start": "2026-11-03T09:00", "reminders": []any{30.0, 1440.0}, "recurrence": "weekly"}, true)
	if err != nil {
		t.Fatal(err)
	}
	if f.End.Sub(f.Start) != time.Hour || f.AllDay || len(f.Reminders) != 2 || f.Recurrence[0] != "RRULE:FREQ=WEEKLY" {
		t.Fatalf("fields: %+v", f)
	}
	f, err = ParseFields(map[string]any{"summary": "Holiday", "start": "2026-12-24", "end": "2026-12-26"}, true)
	if err != nil || !f.AllDay || f.End.Format("2006-01-02") != "2026-12-27" {
		t.Fatalf("all-day, its last day given: %+v %v", f, err)
	}
	for _, bad := range []map[string]any{
		{"summary": "x"},
		{"start": "2026-11-03"},
		{"summary": "x", "start": "tomorrow"},
		{"summary": "x", "start": "2026-11-03T10:00", "end": "2026-11-03T09:00"},
		{"summary": "x", "start": "2026-11-03", "recurrence": "hourly"},
	} {
		if _, err := ParseFields(bad, true); err == nil {
			t.Errorf("accepted %v", bad)
		}
	}
	if got := MeetingURL("", "Join: https://meet.google.com/abc-defg-hij, thanks"); got != "https://meet.google.com/abc-defg-hij" {
		t.Errorf("meeting url: %q", got)
	}
}

func TestSeriesTimesFromAnOccurrence(t *testing.T) {
	withCopy(t, nil, nil, func() {
		series := Event{Start: "2026-10-19T09:30:00+02:00", End: "2026-10-19T09:45:00+02:00", Recurrence: []string{"RRULE:FREQ=DAILY"}}
		// The occurrence of Nov 4 (winter time) moved to 10:00-10:30.
		op := map[string]any{"occurrence": "2026-11-04T09:30:00+01:00", "all": true, "start": "2026-11-04T10:00", "end": "2026-11-04T10:30"}
		if err := seriesTimes(series, op); err != nil {
			t.Fatal(err)
		}
		if op["start"] != "2026-10-19T10:00" || op["end"] != "2026-10-19T10:30" {
			t.Fatalf("the series' first: %v %v", op["start"], op["end"])
		}
		if _, has := op["occurrence"]; has {
			t.Fatalf("the occurrence kept: %v", op)
		}
	})
}
