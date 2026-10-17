package local

import (
	"fmt"
	"slices"
	"strings"
	"time"

	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/core"
	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/registry"
	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/tasks"
)

const tasksFile = "tasks.json"

func init() {
	tasks.Register("local", func(registry.Account) (tasks.Provider, error) { return localTasks{}, nil }, nil)
}

type tasksData struct {
	Lists []tasks.List `json:"lists"`
	Tasks []tasks.Task `json:"tasks"`
}

type localTasks struct{}

// loadTasks is the file; a first list ("Tasks") when there is none.
func loadTasks() (*tasksData, error) {
	d := &tasksData{}
	if _, err := read(tasksFile, d); err != nil {
		return nil, err
	}
	if len(d.Lists) == 0 {
		d.Lists = []tasks.List{{ID: "tasks", Name: "Tasks"}}
	}
	if d.Tasks == nil {
		d.Tasks = []tasks.Task{}
	}
	return d, nil
}

func fillTasks(sec *tasks.Section, d *tasksData) {
	for i := range d.Lists {
		d.Lists[i].Order = i
	}
	sec.Lists, sec.Tasks = slices.Clone(d.Lists), slices.Clone(d.Tasks)
	sec.SyncedAt = time.Now().UnixMilli()
}

func (localTasks) Sync(sec *tasks.Section, full bool) (int, bool, error) {
	d, err := loadTasks()
	if err != nil {
		return 0, false, err
	}
	changed := len(d.Tasks) - len(sec.Tasks)
	fillTasks(sec, d)
	return max(changed, 0), true, nil
}

func dueOf(op map[string]any) (string, bool, error) {
	due, has, err := str(op, "due")
	if err != nil || !has || due == "" {
		return due, has, err
	}
	if _, err := time.Parse("2006-01-02", due); err != nil {
		return "", true, core.Errorf("`due` must be YYYY-MM-DD (or \"\" to clear)")
	}
	return due, true, nil
}

func (localTasks) Apply(sec *tasks.Section, op map[string]any) (any, error) {
	d, err := loadTasks()
	if err != nil {
		return nil, err
	}
	listRef, _, _ := str(op, "list")
	findList := func(id string) int {
		if id == "" {
			return 0
		}
		return slices.IndexFunc(d.Lists, func(l tasks.List) bool { return l.ID == id })
	}
	var res any
	switch kind := kindOf(op); kind {
	case "create_list":
		name, _, _ := str(op, "name")
		if name = strings.TrimSpace(name); name == "" {
			return nil, core.Errorf("`name` is required")
		}
		if slices.ContainsFunc(d.Lists, func(l tasks.List) bool { return strings.EqualFold(l.Name, name) }) {
			return nil, core.Errorf("there is already a list '%s'", name)
		}
		l := tasks.List{ID: newID(), Name: name, Order: len(d.Lists)}
		d.Lists = append(d.Lists, l)
		res = l
	case "rename_list", "delete_list":
		i := findList(listRef)
		if i < 0 || listRef == "" {
			return nil, core.Errorf("no list '%s'", listRef)
		}
		if kind == "delete_list" {
			if len(d.Lists) == 1 {
				return nil, core.Errorf("the last list can't be deleted")
			}
			l := d.Lists[i]
			n := len(d.Tasks)
			d.Tasks = slices.DeleteFunc(d.Tasks, func(t tasks.Task) bool { return t.ListID == l.ID })
			d.Lists = slices.Delete(d.Lists, i, i+1)
			res = map[string]any{"deleted": l.ID, "name": l.Name, "tasks": n - len(d.Tasks)}
		} else {
			name, _, _ := str(op, "name")
			if name = strings.TrimSpace(name); name == "" {
				return nil, core.Errorf("`name` is required")
			}
			d.Lists[i].Name = name
			res = d.Lists[i]
		}
	case "create":
		title, _, _ := str(op, "title")
		if title = strings.TrimSpace(title); title == "" {
			return nil, core.Errorf("a new task needs a title")
		}
		i := findList(listRef)
		if i < 0 {
			return nil, core.Errorf("no list '%s'", listRef)
		}
		notes, _, _ := str(op, "notes")
		due, _, err := dueOf(op)
		if err != nil {
			return nil, err
		}
		parent, _, _ := str(op, "parent")
		t := tasks.Task{
			ID: newID(), ListID: d.Lists[i].ID, Title: title, Notes: notes, Due: due, Parent: parent,
			Position: fmt.Sprintf("%020d", time.Now().UnixNano()), Updated: now(),
		}
		if done, _ := op["done"].(bool); done {
			t.Done, t.Completed = true, now()
		}
		d.Tasks = append(d.Tasks, t)
		res = t
	default:
		id, _, _ := str(op, "id")
		i := slices.IndexFunc(d.Tasks, func(t tasks.Task) bool { return t.ID == id })
		if i < 0 {
			return nil, core.Errorf("no task '%s'", id)
		}
		t := &d.Tasks[i]
		switch kind {
		case "delete":
			res = map[string]any{"deleted": t.ID, "title": t.Title}
			gone := t.ID
			d.Tasks = slices.DeleteFunc(d.Tasks, func(x tasks.Task) bool { return x.ID == gone || x.Parent == gone })
		case "done", "undone":
			t.Done = kind == "done"
			t.Completed = ""
			if t.Done {
				t.Completed = now()
			}
			t.Updated = now()
			res = *t
		case "move":
			j := findList(listRef)
			if j < 0 || listRef == "" {
				return nil, core.Errorf("no list '%s'", listRef)
			}
			t.ListID, t.Updated = d.Lists[j].ID, now()
			for k := range d.Tasks {
				if d.Tasks[k].Parent == t.ID {
					d.Tasks[k].ListID = t.ListID
				}
			}
			res = *t
		case "update":
			title, hasTitle, _ := str(op, "title")
			notes, hasNotes, _ := str(op, "notes")
			due, hasDue, err := dueOf(op)
			if err != nil {
				return nil, err
			}
			if !hasTitle && !hasNotes && !hasDue {
				return nil, core.Errorf("nothing to change: give title, notes or due")
			}
			if hasTitle {
				if title = strings.TrimSpace(title); title == "" {
					return nil, core.Errorf("the title can't be empty")
				}
				t.Title = title
			}
			if hasNotes {
				t.Notes = notes
			}
			if hasDue {
				t.Due = due
			}
			t.Updated = now()
			res = *t
		default:
			return nil, core.Errorf("unknown op '%s'", kind)
		}
	}
	if err := write(tasksFile, d); err != nil {
		return nil, err
	}
	fillTasks(sec, d)
	return res, nil
}
