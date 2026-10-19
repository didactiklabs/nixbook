package google

import (
	"net/url"
	"slices"
	"strings"
	"time"

	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/core"
	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/registry"
	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/tasks"
)

// Completed tasks older than this aren't fetched (the shell shows 14 days).
const keepCompleted = 30 * 24 * time.Hour

// A sync asks for the changes since a little before the last one: clocks
// differ, and a change made during the last sync must not be missed.
const syncOverlap = 5 * time.Minute

func tasksAPI() string {
	return core.Endpoint("NIXBOOK_ACCOUNTS_GOOGLE_TASKS_API", "https://tasks.googleapis.com/tasks/v1")
}

func init() {
	tasks.Register("google", func(a registry.Account) (tasks.Provider, error) {
		return &googleTasks{account: a}, nil
	}, nil)
}

// googleTasks is a Google account's task lists. The Tasks API has no sync
// tokens: a sync asks each list for what changed since the last one
// (deletions included), everything for a new list.
type googleTasks struct {
	account registry.Account
	token   string
}

func (g *googleTasks) call(method, path string, body any, out any) error {
	if g.token == "" {
		t, err := AccessToken(g.account)
		if err != nil {
			return err
		}
		g.token = t
	}
	return core.Call(method, tasksAPI()+path, body, nil, g.token, out)
}

func esc(id string) string { return url.PathEscape(id) }

// dueDate is Google's due time (that day's UTC midnight) as YYYY-MM-DD.
func dueDate(due string) string {
	if len(due) >= 10 {
		return due[:10]
	}
	return ""
}

func fromGoogle(listID string, t obj) tasks.Task {
	return tasks.Task{
		ID: str(t, "id"), ListID: listID, Title: str(t, "title"), Notes: str(t, "notes"),
		Due: dueDate(str(t, "due")), Done: str(t, "status") == "completed", Completed: str(t, "completed"),
		Parent: str(t, "parent"), Position: str(t, "position"), Updated: str(t, "updated"),
	}
}

// -- sync ------------------------------------------------------------------

func (g *googleTasks) lists() ([]tasks.List, error) {
	out, page := []tasks.List{}, ""
	for {
		q := url.Values{"maxResults": {"100"}}
		if page != "" {
			q.Set("pageToken", page)
		}
		var r struct {
			Items []obj  `json:"items"`
			Next  string `json:"nextPageToken"`
		}
		if err := g.call("GET", "/users/@me/lists?"+q.Encode(), nil, &r); err != nil {
			return nil, err
		}
		for _, l := range r.Items {
			out = append(out, tasks.List{ID: str(l, "id"), Name: str(l, "title"), Order: len(out)})
		}
		if page = r.Next; page == "" {
			return out, nil
		}
	}
}

// listTasks is a list's tasks, or (since set) those changed since then,
// deleted ones included (deleted or hidden: to drop).
func (g *googleTasks) listTasks(listID string, since time.Time) ([]obj, error) {
	out, page := []obj{}, ""
	for {
		// No completedMin: Google then leaves out every task not completed
		// (old completed ones are dropped here instead).
		q := url.Values{"maxResults": {"100"}, "showCompleted": {"true"}, "showHidden": {"true"}}
		if !since.IsZero() {
			q.Set("updatedMin", since.UTC().Format(time.RFC3339))
			q.Set("showDeleted", "true")
		}
		if page != "" {
			q.Set("pageToken", page)
		}
		var r struct {
			Items []obj  `json:"items"`
			Next  string `json:"nextPageToken"`
		}
		if err := g.call("GET", "/lists/"+esc(listID)+"/tasks?"+q.Encode(), nil, &r); err != nil {
			return nil, err
		}
		out = append(out, r.Items...)
		if page = r.Next; page == "" {
			return out, nil
		}
	}
}

// Sync: what changed in each list since the last sync, everything for a
// new list or when full.
func (g *googleTasks) Sync(sec *tasks.Section, full bool) (int, bool, error) {
	started := time.Now()
	since := time.UnixMilli(sec.SyncedAt).Add(-syncOverlap)
	full = full || sec.SyncedAt == 0
	lists, err := g.lists()
	if err != nil {
		return 0, false, err
	}
	known := map[string]bool{}
	for _, l := range sec.Lists {
		known[l.ID] = true
	}
	byList := map[string][]tasks.Task{}
	for _, t := range sec.Tasks {
		byList[t.ListID] = append(byList[t.ListID], t)
	}
	all, changed := []tasks.Task{}, 0
	for _, l := range lists {
		var from time.Time
		current := map[string]tasks.Task{}
		if !full && known[l.ID] {
			from = since
			for _, t := range byList[l.ID] {
				current[t.ID] = t
			}
		}
		items, err := g.listTasks(l.ID, from)
		if err != nil {
			return 0, false, err
		}
		for _, item := range items {
			id := str(item, "id")
			deleted, _ := item["deleted"].(bool)
			hidden, _ := item["hidden"].(bool)
			if deleted || hidden {
				if _, ok := current[id]; ok {
					delete(current, id)
					changed++
				}
				continue
			}
			t := fromGoogle(l.ID, item)
			if t.Done && t.Completed != "" {
				if when, err := time.Parse(time.RFC3339, t.Completed); err == nil && when.Before(time.Now().Add(-keepCompleted)) {
					delete(current, id)
					continue
				}
			}
			current[id] = t
			changed++
		}
		for _, t := range current {
			all = append(all, t)
		}
	}
	sec.Lists, sec.Tasks = lists, all
	sec.SyncedAt = started.UnixMilli()
	return changed, full, nil
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

// text is a string field: (value, given), checked.
func text(op obj, key string, max int) (string, bool, error) {
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
	if len(s) > max {
		return "", true, core.Errorf("`%s`: at most %d characters", key, max)
	}
	return s, true, nil
}

// dueValue is Google's due time for YYYY-MM-DD ("" clears).
func dueValue(day string) (any, error) {
	if day == "" {
		return nil, nil
	}
	d, err := time.Parse("2006-01-02", day)
	if err != nil {
		return nil, core.Errorf("`due` must be YYYY-MM-DD (or \"\" to clear)")
	}
	return d.Format("2006-01-02") + "T00:00:00.000Z", nil
}

// Apply runs one change on Google, its answer put in the section.
func (g *googleTasks) Apply(sec *tasks.Section, op obj) (any, error) {
	kind := core.Kind(op)
	title, hasTitle, err := text(op, "title", 1024)
	if err != nil {
		return nil, err
	}
	notes, hasNotes, err := text(op, "notes", 8192)
	if err != nil {
		return nil, err
	}
	due, hasDue, err := text(op, "due", 10)
	if err != nil {
		return nil, err
	}
	name, _, err := text(op, "name", 1024)
	if err != nil {
		return nil, err
	}

	switch kind {
	case "create_list":
		if name = strings.TrimSpace(name); name == "" {
			return nil, core.Errorf("`name` is required")
		}
		for _, l := range sec.Lists {
			if strings.EqualFold(l.Name, name) {
				return nil, core.Errorf("there is already a list '%s'", name)
			}
		}
		var r obj
		if err := g.call("POST", "/users/@me/lists", obj{"title": name}, &r); err != nil {
			return nil, err
		}
		l := tasks.List{ID: str(r, "id"), Name: str(r, "title"), Order: len(sec.Lists)}
		sec.Lists = append(sec.Lists, l)
		return l, nil
	case "rename_list", "delete_list":
		l, err := listByID(sec, str(op, "list"))
		if err != nil {
			return nil, err
		}
		if kind == "delete_list" {
			if err := g.call("DELETE", "/users/@me/lists/"+esc(l.ID), nil, nil); err != nil {
				return nil, err
			}
			sec.Lists = slices.DeleteFunc(sec.Lists, func(x tasks.List) bool { return x.ID == l.ID })
			n := len(sec.Tasks)
			sec.Tasks = slices.DeleteFunc(sec.Tasks, func(t tasks.Task) bool { return t.ListID == l.ID })
			return obj{"deleted": l.ID, "name": l.Name, "tasks": n - len(sec.Tasks)}, nil
		}
		if name = strings.TrimSpace(name); name == "" {
			return nil, core.Errorf("`name` is required")
		}
		if err := g.call("PATCH", "/users/@me/lists/"+esc(l.ID), obj{"title": name}, nil); err != nil {
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
		l, err := listByID(sec, str(op, "list"))
		if err != nil {
			return nil, err
		}
		body := obj{"title": title}
		if notes != "" {
			body["notes"] = notes
		}
		if due != "" {
			if body["due"], err = dueValue(due); err != nil {
				return nil, err
			}
		}
		if done, _ := op["done"].(bool); done {
			body["status"] = "completed"
		}
		q := url.Values{}
		if parent := str(op, "parent"); parent != "" {
			q.Set("parent", parent)
		}
		var r obj
		if err := g.call("POST", "/lists/"+esc(l.ID)+"/tasks?"+q.Encode(), body, &r); err != nil {
			return nil, err
		}
		t := fromGoogle(l.ID, r)
		sec.Upsert(t)
		return t, nil
	}

	id := str(op, "id")
	i := slices.IndexFunc(sec.Tasks, func(t tasks.Task) bool { return t.ID == id })
	if i < 0 {
		return nil, core.Errorf("no task '%s' (list or sync first)", id)
	}
	t := sec.Tasks[i]
	path := "/lists/" + esc(t.ListID) + "/tasks/" + esc(t.ID)
	switch kind {
	case "delete":
		if err := g.call("DELETE", path, nil, nil); err != nil {
			return nil, err
		}
		// Google deletes its subtasks with it.
		sec.Tasks = slices.DeleteFunc(sec.Tasks, func(x tasks.Task) bool { return x.ID == t.ID || x.Parent == t.ID })
		return obj{"deleted": t.ID, "title": t.Title}, nil
	case "move":
		l, err := listByID(sec, str(op, "list"))
		if err != nil {
			return nil, err
		}
		if l.ID == t.ListID {
			return t, nil
		}
		var r obj
		q := url.Values{"destinationTasklist": {l.ID}}
		if err := g.call("POST", path+"/move?"+q.Encode(), nil, &r); err != nil {
			return nil, err
		}
		moved := fromGoogle(l.ID, r)
		sec.Tasks = slices.DeleteFunc(sec.Tasks, func(x tasks.Task) bool { return x.ID == t.ID })
		sec.Upsert(moved)
		return moved, nil
	}

	// update, done, undone: Google's current task, changed and put back
	// whole (a patch can't reliably clear a due date or a completion).
	var cur obj
	if err := g.call("GET", path, nil, &cur); err != nil {
		return nil, err
	}
	switch kind {
	case "done":
		cur["status"] = "completed"
	case "undone":
		cur["status"] = "needsAction"
		delete(cur, "completed")
	default:
		if !hasTitle && !hasNotes && !hasDue {
			return nil, core.Errorf("nothing to change: give title, notes or due")
		}
		if hasTitle {
			if title = strings.TrimSpace(title); title == "" {
				return nil, core.Errorf("the title can't be empty")
			}
			cur["title"] = title
		}
		if hasNotes {
			if notes == "" {
				delete(cur, "notes")
			} else {
				cur["notes"] = notes
			}
		}
		if hasDue {
			v, err := dueValue(due)
			if err != nil {
				return nil, err
			}
			if v == nil {
				delete(cur, "due")
			} else {
				cur["due"] = v
			}
		}
	}
	var r obj
	if err := g.call("PUT", path, cur, &r); err != nil {
		return nil, err
	}
	updated := fromGoogle(t.ListID, r)
	sec.Upsert(updated)
	return updated, nil
}
