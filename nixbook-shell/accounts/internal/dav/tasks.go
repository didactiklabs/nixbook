package dav

import (
	"fmt"
	"path"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/emersion/go-ical"
	"github.com/emersion/go-webdav/caldav"

	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/core"
	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/registry"
	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/tasks"
)

func init() {
	tasks.Register("dav", func(a registry.Account) (tasks.Provider, error) {
		return &todos{account: a}, nil
	}, func(a registry.Account) bool { return a.CalendarHome != "" })
}

// Completed to-dos older than this aren't kept (the shell shows 14 days).
const keepCompleted = 30 * 24 * time.Hour

// todos is a DAV account's task lists: its calendars that hold to-dos
// (VTODO, CalDAV), read whole at each sync. A task's id is its path on the
// server; a subtask's parent is said by RELATED-TO (the parent's UID).
type todos struct {
	account registry.Account
	client  *caldav.Client
}

func (p *todos) cc() (*caldav.Client, error) {
	if p.client == nil {
		c, err := calClient(p.account)
		if err != nil {
			return nil, err
		}
		p.client = c
	}
	return p.client, nil
}

// holdsToDos: a calendar that says it takes VTODO (or says nothing).
func holdsToDos(c caldav.Calendar) bool {
	return len(c.SupportedComponentSet) == 0 || slices.ContainsFunc(c.SupportedComponentSet, func(s string) bool {
		return strings.EqualFold(s, ical.CompToDo)
	})
}

func (p *todos) lists() ([]tasks.List, error) {
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
	out := []tasks.List{}
	for _, cal := range cals {
		if !holdsToDos(cal) {
			continue
		}
		name := cal.Name
		if name == "" {
			name = path.Base(strings.TrimRight(cal.Path, "/"))
		}
		out = append(out, tasks.List{ID: strings.TrimRight(cal.Path, "/") + "/", Name: name, Order: len(out)})
	}
	return out, nil
}

func todoOf(cal *ical.Calendar) *ical.Component {
	if cal == nil {
		return nil
	}
	for _, c := range cal.Children {
		if c.Name == ical.CompToDo {
			return c
		}
	}
	return nil
}

func text(comp *ical.Component, name string) string {
	v, _ := comp.Props.Text(name)
	return v
}

// dueDay is DUE (a date or a date-time) as the local YYYY-MM-DD.
func dueDay(comp *ical.Component) string {
	prop := comp.Props.Get(ical.PropDue)
	if prop == nil {
		return ""
	}
	if t, err := prop.DateTime(time.Local); err == nil {
		return t.In(time.Local).Format("2006-01-02")
	}
	if len(prop.Value) >= 8 {
		v := prop.Value
		return v[0:4] + "-" + v[4:6] + "-" + v[6:8]
	}
	return ""
}

func fromToDo(id, listID string, comp *ical.Component, parents map[string]string) tasks.Task {
	t := tasks.Task{
		ID: id, ListID: listID, Title: text(comp, ical.PropSummary), Notes: text(comp, ical.PropDescription), Due: dueDay(comp),
	}
	status := strings.ToUpper(text(comp, ical.PropStatus))
	if prop := comp.Props.Get(ical.PropCompleted); prop != nil {
		if when, err := prop.DateTime(time.UTC); err == nil {
			t.Completed = when.UTC().Format(time.RFC3339)
		}
	}
	t.Done = status == "COMPLETED" || (status == "" && t.Completed != "")
	for _, rel := range comp.Props.Values(ical.PropRelatedTo) {
		if rt := strings.ToUpper(rel.Params.Get("RELTYPE")); rt == "" || rt == "PARENT" {
			t.Parent = parents[rel.Value]
		}
	}
	// Apple's order, else the creation time.
	if v := text(comp, "X-APPLE-SORT-ORDER"); v != "" {
		if n, err := strconv.ParseInt(v, 10, 64); err == nil {
			t.Position = fmt.Sprintf("%020d", n)
		}
	}
	if t.Position == "" {
		if prop := comp.Props.Get(ical.PropCreated); prop != nil {
			t.Position = prop.Value
		} else if prop := comp.Props.Get(ical.PropDateTimeStamp); prop != nil {
			t.Position = prop.Value
		}
	}
	if prop := comp.Props.Get(ical.PropLastModified); prop != nil {
		if when, err := prop.DateTime(time.UTC); err == nil {
			t.Updated = when.UTC().Format(time.RFC3339)
		}
	}
	return t
}

// Sync reads every list's to-dos (CalDAV has them small; no sync tokens
// needed): the completed ones of the last 30 days, the rest all.
func (p *todos) Sync(sec *tasks.Section, full bool) (int, bool, error) {
	lists, err := p.lists()
	if err != nil {
		return 0, false, err
	}
	cc, _ := p.cc()
	c, cancel := ctx()
	defer cancel()
	before := map[string]string{}
	for _, t := range sec.Tasks {
		before[t.ID] = t.Updated + t.Title + t.Due + strconv.FormatBool(t.Done)
	}
	type item struct {
		path, list string
		comp       *ical.Component
	}
	items, uids := []item{}, map[string]string{}
	for _, l := range lists {
		objs, err := cc.QueryCalendar(c, l.ID, &caldav.CalendarQuery{
			CompRequest: caldav.CalendarCompRequest{Name: ical.CompCalendar, AllProps: true, AllComps: true},
			CompFilter:  caldav.CompFilter{Name: ical.CompCalendar, Comps: []caldav.CompFilter{{Name: ical.CompToDo}}},
		})
		if err != nil {
			return 0, false, asError(p.account, err)
		}
		for _, o := range objs {
			comp := todoOf(o.Data)
			if comp == nil {
				continue
			}
			items = append(items, item{o.Path, l.ID, comp})
			uids[text(comp, ical.PropUID)] = o.Path
		}
	}
	cutoff := time.Now().Add(-keepCompleted)
	all, changed := []tasks.Task{}, 0
	for _, it := range items {
		t := fromToDo(it.path, it.list, it.comp, uids)
		if t.Done && t.Completed != "" {
			if when, err := time.Parse(time.RFC3339, t.Completed); err == nil && when.Before(cutoff) {
				continue
			}
		}
		if before[t.ID] != t.Updated+t.Title+t.Due+strconv.FormatBool(t.Done) {
			changed++
		}
		delete(before, t.ID)
		all = append(all, t)
	}
	changed += len(before)
	sec.Lists, sec.Tasks = lists, all
	sec.SyncedAt = time.Now().UnixMilli()
	return changed, true, nil
}

// -- changes ---------------------------------------------------------------

func listByID(sec *tasks.Section, id string) (tasks.List, error) {
	for _, l := range sec.Lists {
		if l.ID == id {
			return l, nil
		}
	}
	if id == "" && len(sec.Lists) > 0 {
		return sec.Lists[0], nil
	}
	return tasks.List{}, core.Errorf("no list '%s'", id)
}

func setDue(comp *ical.Component, day string) error {
	if day == "" {
		comp.Props.Del(ical.PropDue)
		return nil
	}
	d, err := time.ParseInLocation("2006-01-02", day, time.Local)
	if err != nil {
		return core.Errorf("`due` must be YYYY-MM-DD (or \"\" to clear)")
	}
	prop := ical.NewProp(ical.PropDue)
	prop.SetDate(d)
	comp.Props.Set(prop)
	return nil
}

func setText(comp *ical.Component, name, v string) {
	if v == "" {
		comp.Props.Del(name)
	} else {
		comp.Props.SetText(name, v)
	}
}

func setDone(comp *ical.Component, done bool) {
	if done {
		comp.Props.SetText(ical.PropStatus, "COMPLETED")
		comp.Props.SetDateTime(ical.PropCompleted, time.Now().UTC())
		comp.Props.SetText(ical.PropPercentComplete, "100")
	} else {
		comp.Props.SetText(ical.PropStatus, "NEEDS-ACTION")
		comp.Props.Del(ical.PropCompleted)
		comp.Props.Del(ical.PropPercentComplete)
	}
}

func touch(comp *ical.Component) {
	now := time.Now().UTC()
	comp.Props.SetDateTime(ical.PropDateTimeStamp, now)
	comp.Props.SetDateTime(ical.PropLastModified, now)
	seq := 0
	if v := text(comp, ical.PropSequence); v != "" {
		seq, _ = strconv.Atoi(v)
	}
	comp.Props.SetText(ical.PropSequence, strconv.Itoa(seq+1))
}

// put writes the to-do and reads the server's copy back.
func (p *todos) put(sec *tasks.Section, objPath, listID string, cal *ical.Calendar) (tasks.Task, error) {
	cc, err := p.cc()
	if err != nil {
		return tasks.Task{}, err
	}
	c, cancel := ctx()
	defer cancel()
	if _, err := cc.PutCalendarObject(c, objPath, cal); err != nil {
		return tasks.Task{}, asError(p.account, err)
	}
	if o, err := cc.GetCalendarObject(c, objPath); err == nil && todoOf(o.Data) != nil {
		cal = o.Data
	}
	t := fromToDo(objPath, listID, todoOf(cal), p.uidPaths(sec))
	sec.Upsert(t)
	return t, nil
}

// uidPaths maps the section's tasks' UIDs to their ids: read from the
// server's copies is too slow, so the parent's UID is its file's name
// when it was made here, else looked up.
func (p *todos) uidPaths(sec *tasks.Section) map[string]string {
	out := map[string]string{}
	for _, t := range sec.Tasks {
		out[strings.TrimSuffix(path.Base(t.ID), ".ics")] = t.ID
	}
	return out
}

func (p *todos) uidOf(id string) string {
	cc, err := p.cc()
	if err != nil {
		return ""
	}
	c, cancel := ctx()
	defer cancel()
	if o, err := cc.GetCalendarObject(c, id); err == nil {
		if comp := todoOf(o.Data); comp != nil {
			return text(comp, ical.PropUID)
		}
	}
	return ""
}

func strOf(op map[string]any, key string) (string, bool, error) {
	v, has := op[key]
	if !has {
		return "", false, nil
	}
	if v == nil {
		return "", true, nil
	}
	s, ok := v.(string)
	if !ok {
		return "", true, core.Errorf("`%s` must be a string", key)
	}
	return s, true, nil
}

// Apply runs one change on the server, its answer put in the section.
func (p *todos) Apply(sec *tasks.Section, op map[string]any) (any, error) {
	kind, _ := op["op"].(string)
	if kind == "" {
		kind, _ = op["action"].(string)
	}
	title, hasTitle, err := strOf(op, "title")
	if err != nil {
		return nil, err
	}
	notes, hasNotes, err := strOf(op, "notes")
	if err != nil {
		return nil, err
	}
	due, hasDue, err := strOf(op, "due")
	if err != nil {
		return nil, err
	}
	name, _, _ := strOf(op, "name")
	listRef, _, _ := strOf(op, "list")
	cc, err := p.cc()
	if err != nil {
		return nil, err
	}
	c, cancel := ctx()
	defer cancel()

	switch kind {
	case "create_list":
		if name = strings.TrimSpace(name); name == "" {
			return nil, core.Errorf("`name` is required")
		}
		if slices.ContainsFunc(sec.Lists, func(l tasks.List) bool { return strings.EqualFold(l.Name, name) }) {
			return nil, core.Errorf("there is already a list '%s'", name)
		}
		listPath := strings.TrimRight(p.account.CalendarHome, "/") + "/" + newUID() + "/"
		body := `<?xml version="1.0" encoding="utf-8"?>
<c:mkcalendar xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:set><d:prop>
<d:displayname>` + xmlText(name) + `</d:displayname>
<c:supported-calendar-component-set><c:comp name="VTODO"/></c:supported-calendar-component-set>
</d:prop></d:set></c:mkcalendar>`
		if err := rawRequest(c, p.account, "MKCALENDAR", p.account.CalendarURL, listPath, body); err != nil {
			return nil, err
		}
		l := tasks.List{ID: listPath, Name: name, Order: len(sec.Lists)}
		sec.Lists = append(sec.Lists, l)
		return l, nil
	case "rename_list", "delete_list":
		l, err := listByID(sec, listRef)
		if err != nil {
			return nil, err
		}
		if kind == "delete_list" {
			if err := cc.RemoveAll(c, l.ID); err != nil {
				return nil, asError(p.account, err)
			}
			sec.Lists = slices.DeleteFunc(sec.Lists, func(x tasks.List) bool { return x.ID == l.ID })
			n := len(sec.Tasks)
			sec.Tasks = slices.DeleteFunc(sec.Tasks, func(t tasks.Task) bool { return t.ListID == l.ID })
			return map[string]any{"deleted": l.ID, "name": l.Name, "tasks": n - len(sec.Tasks)}, nil
		}
		if name = strings.TrimSpace(name); name == "" {
			return nil, core.Errorf("`name` is required")
		}
		body := `<?xml version="1.0" encoding="utf-8"?>
<d:propertyupdate xmlns:d="DAV:"><d:set><d:prop><d:displayname>` + xmlText(name) + `</d:displayname></d:prop></d:set></d:propertyupdate>`
		if err := rawRequest(c, p.account, "PROPPATCH", p.account.CalendarURL, l.ID, body); err != nil {
			return nil, err
		}
		for i := range sec.Lists {
			if sec.Lists[i].ID == l.ID {
				sec.Lists[i].Name = name
			}
		}
		l.Name = name
		return l, nil
	case "create":
		if title = strings.TrimSpace(title); title == "" {
			return nil, core.Errorf("a new task needs a title")
		}
		l, err := listByID(sec, listRef)
		if err != nil {
			return nil, err
		}
		uid := newUID()
		cal := ical.NewCalendar()
		cal.Props.SetText(ical.PropVersion, "2.0")
		cal.Props.SetText(ical.PropProductID, "-//nixbook//nixbook-accounts//EN")
		comp := ical.NewComponent(ical.CompToDo)
		comp.Props.SetText(ical.PropUID, uid)
		comp.Props.SetDateTime(ical.PropCreated, time.Now().UTC())
		comp.Props.SetText(ical.PropSummary, title)
		setText(comp, ical.PropDescription, notes)
		if err := setDue(comp, due); err != nil {
			return nil, err
		}
		done, _ := op["done"].(bool)
		setDone(comp, done)
		if parent, _, _ := strOf(op, "parent"); parent != "" {
			if puid := p.uidOf(parent); puid != "" {
				rel := ical.NewProp(ical.PropRelatedTo)
				rel.Value = puid
				rel.Params.Set("RELTYPE", "PARENT")
				comp.Props.Add(rel)
			}
		}
		touch(comp)
		cal.Children = append(cal.Children, comp)
		return p.put(sec, l.ID+uid+".ics", l.ID, cal)
	}

	id, _, _ := strOf(op, "id")
	i := slices.IndexFunc(sec.Tasks, func(t tasks.Task) bool { return t.ID == id })
	if i < 0 {
		return nil, core.Errorf("no task '%s' (list or sync first)", id)
	}
	t := sec.Tasks[i]
	switch kind {
	case "delete":
		// Its subtasks with it, as Google does.
		gone := []string{t.ID}
		for _, x := range sec.Tasks {
			if x.Parent == t.ID {
				gone = append(gone, x.ID)
			}
		}
		for _, g := range gone {
			if err := cc.RemoveAll(c, g); err != nil {
				return nil, asError(p.account, err)
			}
		}
		sec.Tasks = slices.DeleteFunc(sec.Tasks, func(x tasks.Task) bool { return slices.Contains(gone, x.ID) })
		return map[string]any{"deleted": t.ID, "title": t.Title}, nil
	case "move":
		l, err := listByID(sec, listRef)
		if err != nil {
			return nil, err
		}
		if l.ID == t.ListID {
			return t, nil
		}
		dest := l.ID + path.Base(t.ID)
		if err := cc.Move(c, t.ID, dest, nil); err != nil {
			return nil, asError(p.account, err)
		}
		moved := t
		moved.ID, moved.ListID = dest, l.ID
		sec.Tasks = slices.DeleteFunc(sec.Tasks, func(x tasks.Task) bool { return x.ID == t.ID })
		for j := range sec.Tasks {
			if sec.Tasks[j].Parent == t.ID {
				sec.Tasks[j].Parent = dest
			}
		}
		sec.Upsert(moved)
		return moved, nil
	}

	// update, done, undone: the server's current to-do, changed.
	o, err := cc.GetCalendarObject(c, t.ID)
	if err != nil {
		return nil, asError(p.account, err)
	}
	comp := todoOf(o.Data)
	if comp == nil {
		return nil, core.Errorf("'%s' isn't a to-do any more: sync", t.ID)
	}
	switch kind {
	case "done", "undone":
		setDone(comp, kind == "done")
	case "update":
		if !hasTitle && !hasNotes && !hasDue {
			return nil, core.Errorf("nothing to change: give title, notes or due")
		}
		if hasTitle {
			if title = strings.TrimSpace(title); title == "" {
				return nil, core.Errorf("the title can't be empty")
			}
			comp.Props.SetText(ical.PropSummary, title)
		}
		if hasNotes {
			setText(comp, ical.PropDescription, notes)
		}
		if hasDue {
			if err := setDue(comp, due); err != nil {
				return nil, err
			}
		}
	default:
		return nil, core.Errorf("unknown op '%s'", kind)
	}
	touch(comp)
	return p.put(sec, t.ID, t.ListID, o.Data)
}
