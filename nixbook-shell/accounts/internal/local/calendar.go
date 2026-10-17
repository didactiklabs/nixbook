package local

import (
	"slices"
	"time"

	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/calendar"
	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/core"
	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/registry"
)

const calendarFile = "calendar.json"

func init() {
	calendar.Register("local", func(registry.Account) (calendar.Provider, error) { return localCalendar{}, nil }, nil)
}

type calendarData struct {
	Calendars []calendar.Calendar `json:"calendars"`
	Events    []calendar.Event    `json:"events"`
}

type localCalendar struct{}

// loadCalendar is the file; a first calendar ("Personal", a 10-minute
// reminder by default) when there is none.
func loadCalendar() (*calendarData, error) {
	d := &calendarData{}
	if _, err := read(calendarFile, d); err != nil {
		return nil, err
	}
	if len(d.Calendars) == 0 {
		d.Calendars = []calendar.Calendar{{ID: "personal", Name: "Personal", Color: "#7e57c2", Primary: true, DefaultReminders: []int{10}}}
	}
	if d.Events == nil {
		d.Events = []calendar.Event{}
	}
	return d, nil
}

func fillCalendar(sec *calendar.Section, d *calendarData) {
	for i := range d.Calendars {
		d.Calendars[i].Order = i
	}
	sec.Calendars, sec.Events = slices.Clone(d.Calendars), slices.Clone(d.Events)
	sec.SyncedAt = time.Now().UnixMilli()
}

func (localCalendar) Sync(sec *calendar.Section, full bool) (int, bool, error) {
	d, err := loadCalendar()
	if err != nil {
		return 0, false, err
	}
	changed := len(d.Events) - len(sec.Events)
	fillCalendar(sec, d)
	return max(changed, 0), true, nil
}

func timeText(t time.Time, allDay bool) string {
	if allDay {
		return t.Format("2006-01-02")
	}
	return t.Format(time.RFC3339)
}

// set puts the given fields on the event.
func set(e *calendar.Event, f calendar.Fields, series bool) {
	if f.Summary != nil {
		e.Summary = *f.Summary
	}
	if f.Description != nil {
		e.Description = *f.Description
	}
	if f.Location != nil {
		e.Location = *f.Location
	}
	if f.HasTime {
		e.Start, e.End, e.AllDay = timeText(f.Start, f.AllDay), timeText(f.End, f.AllDay), f.AllDay
		e.TimeZone = f.TimeZone
		if e.TimeZone == "" && !f.AllDay && (series || len(e.Recurrence) > 0 || f.HasRecurrence && len(f.Recurrence) > 0) {
			e.TimeZone = calendar.LocalZone()
		}
	}
	if f.HasReminders {
		if f.DefaultReminders {
			e.Reminders = nil
		} else {
			e.Reminders = f.Reminders
		}
	}
	if f.HasRecurrence && e.RecurringID == "" {
		e.Recurrence = f.Recurrence
		if len(e.Recurrence) == 0 {
			e.Recurrence = nil
		}
	}
	e.MeetingURL = calendar.MeetingURL(e.Location, e.Description)
	e.Updated = time.Now().UTC().Format(time.RFC3339)
}

func (localCalendar) Apply(sec *calendar.Section, op map[string]any) (any, error) {
	d, err := loadCalendar()
	if err != nil {
		return nil, err
	}
	kind := kindOf(op)
	fields, err := calendar.ParseFields(op, kind == "create")
	if err != nil && kind != "delete" {
		return nil, err
	}
	calID, _, _ := str(op, "calendar")
	var res any
	switch kind {
	case "create":
		if !slices.ContainsFunc(d.Calendars, func(c calendar.Calendar) bool { return c.ID == calID }) {
			calID = d.Calendars[0].ID
		}
		e := calendar.Event{ID: newID(), CalendarID: calID}
		set(&e, fields, false)
		d.Events = append(d.Events, e)
		res = e
	case "update", "delete":
		id, _, _ := str(op, "id")
		i := slices.IndexFunc(d.Events, func(e calendar.Event) bool { return e.ID == id })
		if i < 0 {
			return nil, core.Errorf("no event '%s'", id)
		}
		occurrence, _, _ := str(op, "occurrence")
		e := d.Events[i]
		if occurrence != "" && len(e.Recurrence) > 0 {
			// That occurrence alone: an occurrence of its own, changed or
			// cancelled, beside the series.
			j := slices.IndexFunc(d.Events, func(x calendar.Event) bool { return x.RecurringID == e.ID && x.OriginalStart == occurrence })
			if j < 0 {
				start, err := calendar.ParseTime(occurrence)
				if err != nil {
					return nil, core.Errorf("`occurrence` must be the occurrence's start, as events gives it")
				}
				s0, _ := calendar.ParseTime(e.Start)
				e0, _ := calendar.ParseTime(e.End)
				o := e
				o.ID, o.RecurringID, o.OriginalStart, o.Recurrence = newID(), e.ID, occurrence, nil
				o.Start, o.End = timeText(start, e.AllDay), timeText(start.Add(e0.Sub(s0)), e.AllDay)
				d.Events = append(d.Events, o)
				j = len(d.Events) - 1
			}
			if kind == "delete" {
				d.Events[j].Cancelled = true
				res = map[string]any{"deleted": e.ID, "occurrence": occurrence, "summary": e.Summary}
			} else {
				set(&d.Events[j], fields, false)
				res = d.Events[j]
			}
			break
		}
		if kind == "delete" {
			d.Events = slices.DeleteFunc(d.Events, func(x calendar.Event) bool { return x.ID == e.ID || x.RecurringID == e.ID })
			res = map[string]any{"deleted": e.ID, "summary": e.Summary}
			break
		}
		if calID != "" && calID != e.CalendarID {
			if !slices.ContainsFunc(d.Calendars, func(c calendar.Calendar) bool { return c.ID == calID }) {
				return nil, core.Errorf("no calendar '%s'", calID)
			}
			for k := range d.Events {
				if d.Events[k].ID == e.ID || d.Events[k].RecurringID == e.ID {
					d.Events[k].CalendarID = calID
				}
			}
		}
		set(&d.Events[i], fields, len(e.Recurrence) > 0)
		res = d.Events[i]
	default:
		return nil, core.Errorf("unknown op '%s'", kind)
	}
	if err := write(calendarFile, d); err != nil {
		return nil, err
	}
	fillCalendar(sec, d)
	return res, nil
}
