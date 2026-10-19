package dav

import (
	"fmt"
	"path"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/emersion/go-ical"
	"github.com/emersion/go-webdav/caldav"

	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/calendar"
	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/core"
	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/registry"
)

func init() {
	calendar.Register("dav", func(a registry.Account) (calendar.Provider, error) {
		return &events{account: a}, nil
	}, func(a registry.Account) bool { return a.CalendarHome != "" })
}

// The window a sync reads (the server tests series against it).
const (
	syncPast   = 400 * 24 * time.Hour
	syncFuture = 3 * 365 * 24 * time.Hour
)

// events is a DAV account's calendars that hold events (VEVENT, CalDAV),
// read within a window at each sync. An event's id is its file's path on
// the server; a changed occurrence of a series (same file, RECURRENCE-ID)
// is "<path>#<original start>".
type events struct {
	account registry.Account
	client  *caldav.Client
}

func (p *events) cc() (*caldav.Client, error) {
	if p.client == nil {
		c, err := calClient(p.account)
		if err != nil {
			return nil, err
		}
		p.client = c
	}
	return p.client, nil
}

func holdsEvents(c caldav.Calendar) bool {
	return len(c.SupportedComponentSet) == 0 || slices.ContainsFunc(c.SupportedComponentSet, func(s string) bool {
		return strings.EqualFold(s, ical.CompEvent)
	})
}

func (p *events) calendars() ([]calendar.Calendar, error) {
	cc, err := p.cc()
	if err != nil {
		return nil, err
	}
	c, cancel := ctx()
	defer cancel()
	cals, err := cc.FindCalendars(c, p.account.CalendarHome)
	if err != nil {
		return nil, asError(p.account, err)
	}
	out := []calendar.Calendar{}
	for _, cal := range cals {
		if !holdsEvents(cal) {
			continue
		}
		name := cal.Name
		if name == "" {
			name = path.Base(strings.TrimRight(cal.Path, "/"))
		}
		out = append(out, calendar.Calendar{
			ID: strings.TrimRight(cal.Path, "/") + "/", Name: name, Order: len(out),
			Primary: len(out) == 0, DefaultReminders: []int{},
		})
	}
	return out, nil
}

// -- iCalendar <-> event ---------------------------------------------------

// icalTime is a DTSTART-like property: RFC 3339 or a date, all-day, zone.
func icalTime(prop *ical.Prop) (string, bool, string) {
	if prop == nil {
		return "", false, ""
	}
	if prop.ValueType() == ical.ValueDate || (len(prop.Value) == 8 && !strings.Contains(prop.Value, "T")) {
		v := prop.Value
		if len(v) >= 8 {
			return v[0:4] + "-" + v[4:6] + "-" + v[6:8], true, ""
		}
		return "", true, ""
	}
	t, err := prop.DateTime(time.Local)
	if err != nil {
		return "", false, ""
	}
	return t.Format(time.RFC3339), false, prop.Params.Get(ical.PropTimezoneID)
}

// recurrenceLines are a VEVENT's RRULE, EXDATE and RDATE as lines.
func recurrenceLines(comp *ical.Component) []string {
	out := []string{}
	for _, name := range []string{ical.PropRecurrenceRule, ical.PropExceptionDates, ical.PropRecurrenceDates} {
		for _, prop := range comp.Props.Values(name) {
			params := ""
			if tz := prop.Params.Get(ical.PropTimezoneID); tz != "" {
				params += ";TZID=" + tz
			}
			if prop.ValueType() == ical.ValueDate {
				params += ";VALUE=DATE"
			}
			// One date per line: EXDATE:a,b becomes two.
			if name == ical.PropRecurrenceRule {
				out = append(out, name+params+":"+prop.Value)
				continue
			}
			for _, v := range strings.Split(prop.Value, ",") {
				out = append(out, name+params+":"+v)
			}
		}
	}
	return out
}

var triggerRe = regexp.MustCompile(`^-?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$`)

// reminders are a VEVENT's alarms before its start, in minutes; nil when it
// has none.
func reminders(comp *ical.Component) []int {
	var out []int
	for _, a := range comp.Children {
		if a.Name != ical.CompAlarm {
			continue
		}
		trigger := a.Props.Get(ical.PropTrigger)
		if trigger == nil || strings.EqualFold(trigger.Params.Get("RELATED"), "END") {
			continue
		}
		m := triggerRe.FindStringSubmatch(strings.TrimSpace(trigger.Value))
		if m == nil || !strings.HasPrefix(trigger.Value, "-") && trigger.Value != "PT0S" && trigger.Value != "P0D" {
			continue
		}
		n := func(i int) int { v, _ := strconv.Atoi(m[i]); return v }
		minutes := n(1)*7*24*60 + n(2)*24*60 + n(3)*60 + n(4) + n(5)/60
		if out == nil {
			out = []int{}
		}
		if !slices.Contains(out, minutes) {
			out = append(out, minutes)
		}
	}
	return out
}

func fromVEvent(objPath, calID string, comp *ical.Component) calendar.Event {
	start, allDay, tz := icalTime(comp.Props.Get(ical.PropDateTimeStart))
	end, _, _ := icalTime(comp.Props.Get(ical.PropDateTimeEnd))
	if end == "" {
		if s, err := calendar.ParseTime(start); err == nil {
			switch d := comp.Props.Get(ical.PropDuration); {
			case d != nil:
				if dur, err := d.Duration(); err == nil {
					end = s.Add(dur).Format(time.RFC3339)
				}
			case allDay:
				end = s.AddDate(0, 0, 1).Format("2006-01-02")
			default:
				end = start
			}
			if allDay && len(end) > 10 {
				end = end[:10]
			}
		}
	}
	e := calendar.Event{
		ID: objPath, CalendarID: calID, Summary: text(comp, ical.PropSummary), Description: text(comp, ical.PropDescription),
		Location: text(comp, ical.PropLocation), Start: start, End: end, AllDay: allDay, TimeZone: tz,
		Cancelled: strings.EqualFold(text(comp, ical.PropStatus), "CANCELLED"), Reminders: reminders(comp),
	}
	if rid := comp.Props.Get(ical.PropRecurrenceID); rid != nil {
		e.OriginalStart, _, _ = icalTime(rid)
		e.RecurringID = objPath
		e.ID = objPath + "#" + e.OriginalStart
	} else {
		e.Recurrence = recurrenceLines(comp)
		if len(e.Recurrence) == 0 {
			e.Recurrence = nil
		}
	}
	e.MeetingURL = calendar.MeetingURL(text(comp, ical.PropURL), e.Location, e.Description)
	if prop := comp.Props.Get(ical.PropLastModified); prop != nil {
		if t, err := prop.DateTime(time.UTC); err == nil {
			e.Updated = t.UTC().Format(time.RFC3339)
		}
	}
	return e
}

// -- sync ------------------------------------------------------------------

// Sync reads every calendar's events in the window (series that repeat into
// it included).
func (p *events) Sync(sec *calendar.Section, full bool) (int, bool, error) {
	cals, err := p.calendars()
	if err != nil {
		return 0, false, err
	}
	cc, _ := p.cc()
	c, cancel := ctx()
	defer cancel()
	before := map[string]string{}
	for _, e := range sec.Events {
		before[e.ID] = e.Updated + e.Start + e.Summary
	}
	now := time.Now()
	all, changed := []calendar.Event{}, 0
	for _, cal := range cals {
		objs, err := cc.QueryCalendar(c, cal.ID, &caldav.CalendarQuery{
			CompRequest: caldav.CalendarCompRequest{Name: ical.CompCalendar, AllProps: true, AllComps: true},
			CompFilter: caldav.CompFilter{Name: ical.CompCalendar, Comps: []caldav.CompFilter{{
				Name: ical.CompEvent, Start: now.Add(-syncPast), End: now.Add(syncFuture),
			}}},
		})
		if err != nil {
			return 0, false, asError(p.account, err)
		}
		for _, o := range objs {
			if o.Data == nil {
				continue
			}
			for _, comp := range o.Data.Children {
				if comp.Name != ical.CompEvent {
					continue
				}
				e := fromVEvent(o.Path, cal.ID, comp)
				if before[e.ID] != e.Updated+e.Start+e.Summary {
					changed++
				}
				delete(before, e.ID)
				all = append(all, e)
			}
		}
	}
	changed += len(before)
	sec.Calendars, sec.Events = cals, all
	sec.SyncedAt = time.Now().UnixMilli()
	return changed, true, nil
}

// -- changes ---------------------------------------------------------------

func setTime(comp *ical.Component, name string, t time.Time, allDay bool, tz string) {
	prop := ical.NewProp(name)
	switch {
	case allDay:
		prop.SetDate(t)
	case tz != "":
		if loc, err := time.LoadLocation(tz); err == nil {
			prop.Value = t.In(loc).Format("20060102T150405")
			prop.Params.Set(ical.PropTimezoneID, tz)
			break
		}
		prop.SetDateTime(t.UTC())
	default:
		prop.SetDateTime(t.UTC())
	}
	comp.Props.Set(prop)
}

func setAlarms(comp *ical.Component, minutes []int) {
	comp.Children = slices.DeleteFunc(comp.Children, func(c *ical.Component) bool { return c.Name == ical.CompAlarm })
	for _, m := range minutes {
		a := ical.NewComponent(ical.CompAlarm)
		a.Props.SetText(ical.PropAction, "DISPLAY")
		a.Props.SetText(ical.PropDescription, "Reminder")
		trigger := ical.NewProp(ical.PropTrigger)
		trigger.Value = fmt.Sprintf("-PT%dM", m)
		if m == 0 {
			trigger.Value = "PT0S"
		}
		a.Props.Set(trigger)
		comp.Children = append(comp.Children, a)
	}
}

// applyFields sets the given fields on a VEVENT.
func applyFields(comp *ical.Component, f calendar.Fields, recurring bool) {
	if f.Summary != nil {
		setText(comp, ical.PropSummary, *f.Summary)
	}
	if f.Description != nil {
		setText(comp, ical.PropDescription, *f.Description)
	}
	if f.Location != nil {
		setText(comp, ical.PropLocation, *f.Location)
	}
	if f.HasTime {
		tz := f.TimeZone
		if tz == "" && (recurring || f.HasRecurrence && len(f.Recurrence) > 0) {
			tz = calendar.LocalZone()
		}
		comp.Props.Del(ical.PropDuration)
		setTime(comp, ical.PropDateTimeStart, f.Start, f.AllDay, tz)
		setTime(comp, ical.PropDateTimeEnd, f.End, f.AllDay, tz)
	}
	if f.HasReminders {
		if f.DefaultReminders {
			setAlarms(comp, nil)
		} else {
			setAlarms(comp, f.Reminders)
		}
	}
	if f.HasRecurrence {
		comp.Props.Del(ical.PropRecurrenceRule)
		comp.Props.Del(ical.PropExceptionDates)
		comp.Props.Del(ical.PropRecurrenceDates)
		for _, l := range f.Recurrence {
			name, value, _ := strings.Cut(l, ":")
			params := ical.Params{}
			parts := strings.Split(name, ";")
			for _, kv := range parts[1:] {
				if k, v, ok := strings.Cut(kv, "="); ok {
					params.Set(k, v)
				}
			}
			comp.Props.Add(&ical.Prop{Name: strings.ToUpper(parts[0]), Params: params, Value: value})
		}
	}
	touch(comp)
}

// object is an event's file: the calendar and its VEVENTs, the series first.
func (p *events) object(objPath string) (*ical.Calendar, error) {
	cc, err := p.cc()
	if err != nil {
		return nil, err
	}
	c, cancel := ctx()
	defer cancel()
	o, err := cc.GetCalendarObject(c, objPath)
	if err != nil {
		return nil, asError(p.account, err)
	}
	return o.Data, nil
}

func master(cal *ical.Calendar) *ical.Component {
	for _, c := range cal.Children {
		if c.Name == ical.CompEvent && c.Props.Get(ical.PropRecurrenceID) == nil {
			return c
		}
	}
	return nil
}

// write puts the file back and reads its events into the section.
func (p *events) write(sec *calendar.Section, objPath, calID string, cal *ical.Calendar) (calendar.Event, error) {
	cc, err := p.cc()
	if err != nil {
		return calendar.Event{}, err
	}
	c, cancel := ctx()
	defer cancel()
	if _, err := cc.PutCalendarObject(c, objPath, cal); err != nil {
		return calendar.Event{}, asError(p.account, err)
	}
	if o, err := cc.GetCalendarObject(c, objPath); err == nil && o.Data != nil {
		cal = o.Data
	}
	sec.Events = slices.DeleteFunc(sec.Events, func(e calendar.Event) bool { return e.ID == objPath || e.RecurringID == objPath })
	var first calendar.Event
	for _, comp := range cal.Children {
		if comp.Name != ical.CompEvent {
			continue
		}
		e := fromVEvent(objPath, calID, comp)
		sec.Events = append(sec.Events, e)
		if first.ID == "" || e.RecurringID == "" {
			first = e
		}
	}
	return first, nil
}

// occurrenceProp is a RECURRENCE-ID or EXDATE for that occurrence, in the
// series' form.
func occurrenceProp(name string, series *ical.Component, occurrence string) (*ical.Prop, error) {
	t, err := calendar.ParseTime(occurrence)
	if err != nil {
		return nil, core.Errorf("`occurrence` must be the occurrence's start, as events gives it")
	}
	start := series.Props.Get(ical.PropDateTimeStart)
	prop := ical.NewProp(name)
	switch {
	case start != nil && start.ValueType() == ical.ValueDate:
		prop.SetDate(t)
	case start != nil && start.Params.Get(ical.PropTimezoneID) != "":
		tz := start.Params.Get(ical.PropTimezoneID)
		if loc, err := time.LoadLocation(tz); err == nil {
			prop.Value = t.In(loc).Format("20060102T150405")
			prop.Params.Set(ical.PropTimezoneID, tz)
			break
		}
		prop.SetDateTime(t.UTC())
	default:
		prop.SetDateTime(t.UTC())
	}
	return prop, nil
}

// Apply runs one change on the server, its answer put in the section.
func (p *events) Apply(sec *calendar.Section, op map[string]any) (any, error) {
	kind := core.Kind(op)
	fields, err := calendar.ParseFields(op, kind == "create")
	if err != nil && kind != "delete" {
		return nil, err
	}
	if kind == "create" {
		calID, _ := op["calendar"].(string)
		uid := newUID()
		cal := ical.NewCalendar()
		cal.Props.SetText(ical.PropVersion, "2.0")
		cal.Props.SetText(ical.PropProductID, "-//nixbook//nixbook-accounts//EN")
		comp := ical.NewComponent(ical.CompEvent)
		comp.Props.SetText(ical.PropUID, uid)
		comp.Props.SetDateTime(ical.PropCreated, time.Now().UTC())
		applyFields(comp, fields, false)
		cal.Children = append(cal.Children, comp)
		return p.write(sec, calID+uid+".ics", calID, cal)
	}

	id, _ := op["id"].(string)
	e, ok := sec.Find(id)
	if !ok {
		return nil, core.Errorf("no event '%s' (sync first)", id)
	}
	objPath := e.ID
	occurrence, _ := op["occurrence"].(string)
	if e.RecurringID != "" {
		objPath, occurrence = e.RecurringID, e.OriginalStart
	}
	cal, err := p.object(objPath)
	if err != nil {
		return nil, err
	}
	series := master(cal)
	if series == nil {
		return nil, core.Errorf("'%s' has no event any more: sync", e.Summary)
	}
	cc, _ := p.cc()
	c, cancel := ctx()
	defer cancel()
	switch kind {
	case "delete":
		if occurrence == "" {
			if err := cc.RemoveAll(c, objPath); err != nil {
				return nil, asError(p.account, err)
			}
			sec.Events = slices.DeleteFunc(sec.Events, func(x calendar.Event) bool { return x.ID == objPath || x.RecurringID == objPath })
			return map[string]any{"deleted": objPath, "summary": e.Summary}, nil
		}
		// One occurrence: skipped by the series (EXDATE), its change gone.
		ex, err := occurrenceProp(ical.PropExceptionDates, series, occurrence)
		if err != nil {
			return nil, err
		}
		series.Props.Add(ex)
		touch(series)
		cal.Children = slices.DeleteFunc(cal.Children, func(x *ical.Component) bool {
			rid := x.Props.Get(ical.PropRecurrenceID)
			if x.Name != ical.CompEvent || rid == nil {
				return false
			}
			s, _, _ := icalTime(rid)
			return s == occurrence || strings.HasPrefix(occurrence, s) || strings.HasPrefix(s, occurrence)
		})
		if _, err := p.write(sec, objPath, e.CalendarID, cal); err != nil {
			return nil, err
		}
		return map[string]any{"deleted": objPath, "occurrence": occurrence, "summary": e.Summary}, nil
	case "update":
		to, _ := op["calendar"].(string)
		given := fields.Summary != nil || fields.Description != nil || fields.Location != nil || fields.HasTime || fields.HasReminders || fields.HasRecurrence
		if !given && (to == "" || to == e.CalendarID) {
			return nil, core.Errorf("nothing to change: give the fields to set")
		}
		if given {
			target := series
			if occurrence != "" {
				// That occurrence alone: its own VEVENT (a copy of the
				// series, at that time).
				target = nil
				for _, x := range cal.Children {
					if rid := x.Props.Get(ical.PropRecurrenceID); x.Name == ical.CompEvent && rid != nil {
						if s, _, _ := icalTime(rid); s == occurrence {
							target = x
						}
					}
				}
				if target == nil {
					rid, err := occurrenceProp(ical.PropRecurrenceID, series, occurrence)
					if err != nil {
						return nil, err
					}
					target = ical.NewComponent(ical.CompEvent)
					for name, props := range series.Props {
						if name == ical.PropRecurrenceRule || name == ical.PropExceptionDates || name == ical.PropRecurrenceDates {
							continue
						}
						target.Props[name] = slices.Clone(props)
					}
					target.Children = slices.Clone(series.Children)
					target.Props.Set(rid)
					// The occurrence's own time.
					if t, err := calendar.ParseTime(occurrence); err == nil && series.Props.Get(ical.PropDateTimeStart) != nil {
						s, end, _ := spanOf(series)
						length := end.Sub(s)
						start := series.Props.Get(ical.PropDateTimeStart)
						allDay := start.ValueType() == ical.ValueDate
						tz := start.Params.Get(ical.PropTimezoneID)
						setTime(target, ical.PropDateTimeStart, t, allDay, tz)
						setTime(target, ical.PropDateTimeEnd, t.Add(length), allDay, tz)
						target.Props.Del(ical.PropDuration)
					}
					cal.Children = append(cal.Children, target)
				}
				fields.HasRecurrence = false
			}
			applyFields(target, fields, occurrence == "" && len(e.Recurrence) > 0)
			if _, err := p.write(sec, objPath, e.CalendarID, cal); err != nil {
				return nil, err
			}
		}
		if to != "" && to != e.CalendarID {
			dest := to + path.Base(objPath)
			if err := cc.Move(c, objPath, dest, nil); err != nil {
				return nil, asError(p.account, err)
			}
			for i := range sec.Events {
				if sec.Events[i].ID == objPath || sec.Events[i].RecurringID == objPath {
					sec.Events[i].CalendarID = to
					if sec.Events[i].RecurringID == objPath {
						sec.Events[i].RecurringID = dest
						sec.Events[i].ID = dest + "#" + sec.Events[i].OriginalStart
					} else {
						sec.Events[i].ID = dest
					}
				}
			}
			objPath = dest
		}
		for _, x := range sec.Events {
			if (occurrence == "" && x.ID == objPath) || (occurrence != "" && x.RecurringID == objPath && x.OriginalStart == occurrence) {
				return x, nil
			}
		}
		updated, _ := sec.Find(objPath)
		return updated, nil
	}
	return nil, core.Errorf("unknown op '%s'", kind)
}

// spanOf is a VEVENT's start and end.
func spanOf(comp *ical.Component) (time.Time, time.Time, error) {
	s, err := comp.Props.DateTime(ical.PropDateTimeStart, time.Local)
	if err != nil {
		return s, s, err
	}
	if e, err := comp.Props.DateTime(ical.PropDateTimeEnd, time.Local); err == nil {
		return s, e, nil
	}
	if d := comp.Props.Get(ical.PropDuration); d != nil {
		if dur, err := d.Duration(); err == nil {
			return s, s.Add(dur), nil
		}
	}
	return s, s, nil
}
