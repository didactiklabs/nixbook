package calendar

import (
	"regexp"
	"strings"
	"time"

	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/core"
)

// Fields is a create or update's event fields, those given: what the
// providers write.
type Fields struct {
	Summary, Description, Location *string
	HasTime                        bool
	Start, End                     time.Time
	AllDay                         bool
	Reminders                      []int
	HasReminders, DefaultReminders bool
	Recurrence                     []string
	HasRecurrence                  bool
	TimeZone                       string
}

// InputTime reads a time the shell or an agent gives: RFC 3339,
// "YYYY-MM-DDTHH:MM" (local), or "YYYY-MM-DD".
func InputTime(v string) (time.Time, bool, error) {
	v = strings.TrimSpace(v)
	if t, err := time.Parse(time.RFC3339, v); err == nil {
		return t, false, nil
	}
	for _, layout := range []string{"2006-01-02T15:04", "2006-01-02 15:04", "2006-01-02T15:04:05"} {
		if t, err := time.ParseInLocation(layout, v, time.Local); err == nil {
			return t, false, nil
		}
	}
	if t, err := time.ParseInLocation("2006-01-02", v, time.Local); err == nil {
		return t, true, nil
	}
	return time.Time{}, false, core.Errorf("'%s' isn't a time: YYYY-MM-DD, YYYY-MM-DDTHH:MM or RFC 3339", v)
}

var simpleRules = map[string]string{
	"daily": "RRULE:FREQ=DAILY", "weekdays": "RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR",
	"weekly": "RRULE:FREQ=WEEKLY", "monthly": "RRULE:FREQ=MONTHLY", "yearly": "RRULE:FREQ=YEARLY",
}

// ParseFields reads an op's event fields; a create needs start (end: an
// hour later, the next day all-day).
func ParseFields(op map[string]any, create bool) (Fields, error) {
	f := Fields{}
	str := func(k string) (*string, error) {
		v, has := op[k]
		if !has {
			return nil, nil
		}
		if v == nil {
			s := ""
			return &s, nil
		}
		s, ok := v.(string)
		if !ok {
			return nil, core.Errorf("`%s` must be a string", k)
		}
		if len(s) > 8192 {
			return nil, core.Errorf("`%s`: at most 8192 characters", k)
		}
		return &s, nil
	}
	var err error
	if f.Summary, err = str("summary"); err != nil {
		return f, err
	}
	if f.Summary == nil {
		if f.Summary, err = str("title"); err != nil {
			return f, err
		}
	}
	if f.Description, err = str("description"); err != nil {
		return f, err
	}
	if f.Location, err = str("location"); err != nil {
		return f, err
	}
	start, _ := op["start"].(string)
	end, _ := op["end"].(string)
	allDay, hasAllDay := op["allDay"].(bool)
	if start != "" || end != "" || hasAllDay {
		if start == "" {
			return f, core.Errorf("`start` is needed with `end` or `allDay`")
		}
		f.HasTime = true
		s, dateOnly, err := InputTime(start)
		if err != nil {
			return f, err
		}
		if !hasAllDay {
			allDay = dateOnly
		}
		f.AllDay = allDay
		if allDay {
			s = time.Date(s.Year(), s.Month(), s.Day(), 0, 0, 0, 0, time.Local)
		}
		f.Start = s
		switch {
		case end != "":
			e, _, err := InputTime(end)
			if err != nil {
				return f, err
			}
			if allDay {
				// An all-day event's end is given as its last day (kept as
				// the day after, as calendars do).
				e = time.Date(e.Year(), e.Month(), e.Day(), 0, 0, 0, 0, time.Local).AddDate(0, 0, 1)
			}
			if !e.After(s) {
				return f, core.Errorf("the end must be after the start")
			}
			f.End = e
		case allDay:
			f.End = s.AddDate(0, 0, 1)
		default:
			f.End = s.Add(time.Hour)
		}
	} else if create {
		return f, core.Errorf("a new event needs a `start`")
	}
	if create && (f.Summary == nil || strings.TrimSpace(*f.Summary) == "") {
		return f, core.Errorf("a new event needs a `summary`")
	}
	if v, has := op["reminders"]; has {
		f.HasReminders = true
		switch r := v.(type) {
		case nil:
			f.DefaultReminders = true
		case []any:
			f.Reminders = []int{}
			for _, x := range r {
				n, ok := x.(float64)
				if !ok || n < 0 || n > 40320 {
					return f, core.Errorf("`reminders`: minutes before, 0 to 40320 (4 weeks)")
				}
				f.Reminders = append(f.Reminders, int(n))
			}
		default:
			return f, core.Errorf("`reminders` must be a list of minutes before, or null for the calendar's")
		}
	}
	if v, has := op["recurrence"]; has {
		f.HasRecurrence = true
		var lines []string
		switch r := v.(type) {
		case nil:
		case string:
			lines = []string{r}
		case []any:
			for _, x := range r {
				s, ok := x.(string)
				if !ok {
					return f, core.Errorf("`recurrence` must be daily, weekdays, weekly, monthly, yearly, none or RRULE lines")
				}
				lines = append(lines, s)
			}
		default:
			return f, core.Errorf("`recurrence` must be daily, weekdays, weekly, monthly, yearly, none or RRULE lines")
		}
		f.Recurrence = []string{}
		for _, l := range lines {
			l = strings.TrimSpace(l)
			switch {
			case l == "" || strings.EqualFold(l, "none"):
			case simpleRules[strings.ToLower(l)] != "":
				f.Recurrence = append(f.Recurrence, simpleRules[strings.ToLower(l)])
			case strings.HasPrefix(strings.ToUpper(l), "FREQ="):
				f.Recurrence = append(f.Recurrence, "RRULE:"+l)
			case strings.HasPrefix(strings.ToUpper(l), "RRULE:") || strings.HasPrefix(strings.ToUpper(l), "EXDATE") || strings.HasPrefix(strings.ToUpper(l), "RDATE"):
				f.Recurrence = append(f.Recurrence, l)
			default:
				return f, core.Errorf("'%s' isn't a recurrence: daily, weekdays, weekly, monthly, yearly, none or an RRULE", l)
			}
		}
	}
	if tz, _ := op["timeZone"].(string); tz != "" {
		if _, err := time.LoadLocation(tz); err != nil {
			return f, core.Errorf("unknown time zone '%s'", tz)
		}
		f.TimeZone = tz
	}
	return f, nil
}

// LocalZone is the machine's IANA zone, for series that repeat in it.
func LocalZone() string {
	if tz := core.Getenv("TZ"); tz != "" && !strings.HasPrefix(tz, ":") {
		return tz
	}
	if name := time.Local.String(); name != "Local" {
		return name
	}
	return "UTC"
}

var meetingRe = regexp.MustCompile(`https://(?:meet\.google\.com/[a-z0-9-]+|[\w.-]*zoom\.us/(?:j|my|w)/[^\s<>"']+|teams\.microsoft\.com/l/meetup-join/[^\s<>"']+|teams\.live\.com/meet/[^\s<>"']+|[\w.-]*webex\.com/[^\s<>"']+)`)

// MeetingURL is the first meeting link in the texts.
func MeetingURL(texts ...string) string {
	for _, t := range texts {
		if m := meetingRe.FindString(t); m != "" {
			return m
		}
	}
	return ""
}
