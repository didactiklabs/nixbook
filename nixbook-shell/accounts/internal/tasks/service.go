// Package tasks is the task lists of every account, merged: one local copy
// (tasks.json in the state directory) that the shell's to-do list, Tasks
// window and widgets read, kept in sync by each account's provider (Google
// Tasks, CalDAV…). Changes go to the account's provider first, its answer
// landing in the copy. Ids are global ("<account>:<provider's id>").
package tasks

import (
	"errors"
	"slices"
	"strings"

	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/core"
	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/registry"
)

// CacheFile is the local copy's name in the state directory.
const CacheFile = "tasks.json"

// MaxOps is the most changes one apply runs.
const MaxOps = 50

// List is a task list.
type List struct {
	ID      string `json:"id"`
	Account string `json:"account"`
	Name    string `json:"name"`
	Order   int    `json:"order"`
}

// Task is a task as the shell and agents see it.
type Task struct {
	ID      string `json:"id"`
	Account string `json:"account"`
	ListID  string `json:"listId"`
	Title   string `json:"title"`
	Notes   string `json:"notes"`
	// YYYY-MM-DD, or "": dates, not times.
	Due  string `json:"due"`
	Done bool   `json:"done"`
	// When it was completed (RFC 3339), or "".
	Completed string `json:"completed"`
	// A subtask's parent task id, or "".
	Parent string `json:"parent"`
	// The provider's order within the list.
	Position string `json:"position"`
	Updated  string `json:"updated"`
}

// Section is one account's part of the copy, with the provider's own ids.
type Section struct {
	SyncedAt int64
	Error    string
	Lists    []List
	Tasks    []Task
}

// Upsert puts the task in, replacing the one with its id.
func (s *Section) Upsert(t Task) {
	s.Tasks = slices.DeleteFunc(s.Tasks, func(x Task) bool { return x.ID == t.ID })
	s.Tasks = append(s.Tasks, t)
}

// Meta is an account's sync state in the copy.
type Meta struct {
	SyncedAt int64  `json:"syncedAt"`
	Error    string `json:"error"`
}

// Cache is the local copy: every account's lists and tasks, global ids.
type Cache struct {
	Version  int              `json:"version"`
	Accounts map[string]*Meta `json:"accounts"`
	// The stalest account's last sync, the first account's failure.
	SyncedAt int64  `json:"syncedAt"`
	Error    string `json:"error"`
	Lists    []List `json:"lists"`
	Tasks    []Task `json:"tasks"`
}

// Provider is one account's tasks at its provider.
type Provider interface {
	// Sync brings the provider's changes into the section: how many tasks
	// changed, and whether it fetched everything.
	Sync(sec *Section, full bool) (changed int, fetchedAll bool, err error)
	// Apply runs one change (ops: create, update, done, undone, move,
	// delete, create_list, rename_list, delete_list) with the provider's
	// own ids, updating the section.
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
// given, says whether an account of that kind has tasks at all.
func Register(provider string, f Factory, has func(registry.Account) bool) {
	factories[provider] = entry{f, has}
}

// Supported says whether the account has tasks here.
func Supported(a registry.Account) bool {
	e, ok := factories[a.Provider]
	return ok && (e.has == nil || e.has(a))
}

func providerFor(a registry.Account) (Provider, error) {
	if !Supported(a) {
		return nil, core.Errorf("%s has no tasks here", a.Name)
	}
	return factories[a.Provider].factory(a)
}

// Load is the local copy (empty when there is none yet).
func Load() *Cache {
	c := &Cache{}
	if !core.ReadJSON(CacheFile, c) {
		c = &Cache{}
	}
	c.Version = 2
	if c.Accounts == nil {
		c.Accounts = map[string]*Meta{}
	}
	if c.Lists == nil {
		c.Lists = []List{}
	}
	if c.Tasks == nil {
		c.Tasks = []Task{}
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
	slices.SortStableFunc(c.Lists, func(a, b List) int {
		if accountOrder[a.Account] != accountOrder[b.Account] {
			return accountOrder[a.Account] - accountOrder[b.Account]
		}
		return a.Order - b.Order
	})
	listOrder := map[string]int{}
	for i, l := range c.Lists {
		listOrder[l.ID] = i
	}
	slices.SortStableFunc(c.Tasks, func(a, b Task) int {
		if listOrder[a.ListID] != listOrder[b.ListID] {
			return listOrder[a.ListID] - listOrder[b.ListID]
		}
		return strings.Compare(a.Position, b.Position)
	})
	return core.WriteJSON(CacheFile, c)
}

func local(account, global string) string {
	if strings.HasPrefix(global, account+":") {
		return global[len(account)+1:]
	}
	return ""
}

func section(c *Cache, account string) *Section {
	m := c.Accounts[account]
	if m == nil {
		m = &Meta{}
	}
	s := &Section{SyncedAt: m.SyncedAt, Error: m.Error, Lists: []List{}, Tasks: []Task{}}
	for _, l := range c.Lists {
		if l.Account == account {
			l.ID = local(account, l.ID)
			s.Lists = append(s.Lists, l)
		}
	}
	for _, t := range c.Tasks {
		if t.Account == account {
			t.ID, t.ListID, t.Parent = local(account, t.ID), local(account, t.ListID), local(account, t.Parent)
			s.Tasks = append(s.Tasks, t)
		}
	}
	return s
}

func globalTask(account string, t Task) Task {
	t.Account = account
	t.ID = registry.GlobalID(account, t.ID)
	t.ListID = registry.GlobalID(account, t.ListID)
	t.Parent = registry.GlobalID(account, t.Parent)
	return t
}

func put(c *Cache, account string, s *Section) {
	c.Accounts[account] = &Meta{SyncedAt: s.SyncedAt, Error: s.Error}
	c.Lists = slices.DeleteFunc(c.Lists, func(l List) bool { return l.Account == account })
	for _, l := range s.Lists {
		l.ID, l.Account = registry.GlobalID(account, l.ID), account
		c.Lists = append(c.Lists, l)
	}
	c.Tasks = slices.DeleteFunc(c.Tasks, func(t Task) bool { return t.Account == account })
	for _, t := range s.Tasks {
		c.Tasks = append(c.Tasks, globalTask(account, t))
	}
}

// Forget drops an account's tasks from the copy; every account's with "".
func Forget(account string) error {
	unlock, err := core.Lock("tasks")
	if err != nil {
		return err
	}
	defer unlock()
	c := Load()
	if account == "" {
		c = &Cache{Accounts: map[string]*Meta{}, Lists: []List{}, Tasks: []Task{}}
	} else {
		put(c, account, &Section{})
		delete(c.Accounts, account)
	}
	return save(c)
}

// -- sync ------------------------------------------------------------------

// AccountSync is what a sync did for one account.
type AccountSync struct {
	Account string `json:"account"`
	Full    bool   `json:"full"`
	Changed int    `json:"changed"`
	Lists   int    `json:"lists"`
	Count   int    `json:"count"`
	Error   string `json:"error,omitempty"`
}

// SyncResult is what a sync did.
type SyncResult struct {
	Accounts []AccountSync `json:"accounts"`
	Lists    int           `json:"lists"`
	Count    int           `json:"count"`
	SyncedAt int64         `json:"syncedAt"`
}

// Sync brings each account's changes into the copy (one account's with
// account set). A failing account keeps its tasks and its failure in the
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
			return nil, core.AuthErrorf("no account with tasks connected")
		}
	}
	unlock, err := core.Lock("tasks")
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
		r.Lists, r.Count = len(s.Lists), len(s.Tasks)
		put(c, a.ID, s)
		res.Accounts = append(res.Accounts, r)
	}
	if err := save(c); err != nil {
		return nil, err
	}
	res.Lists, res.Count, res.SyncedAt = len(c.Lists), len(c.Tasks), c.SyncedAt
	if failed == len(accounts) {
		return res, firstErr
	}
	return res, nil
}

// -- changes ---------------------------------------------------------------

// Ops are the changes apply takes, as {"op": …} (or "action").
var Ops = []string{"create", "update", "done", "undone", "move", "delete", "create_list", "rename_list", "delete_list"}

// Result is one change's outcome.
type Result struct {
	OK     bool   `json:"ok"`
	Result any    `json:"result,omitempty"`
	Error  string `json:"error,omitempty"`
}

// Apply runs {op…} or {ops: […]}, in order, each on its own, each at its
// account's provider.
func Apply(request any) ([]Result, error) {
	var ops []any
	if m, ok := request.(map[string]any); ok {
		if v, has := m["ops"]; has {
			ops, _ = v.([]any)
		} else {
			ops = []any{m}
		}
	}
	if len(ops) == 0 || len(ops) > MaxOps {
		return nil, core.Errorf("`ops` must be a list of 1 to %d changes", MaxOps)
	}
	unlock, err := core.Lock("tasks")
	if err != nil {
		return nil, err
	}
	defer unlock()
	c := Load()
	results := make([]Result, 0, len(ops))
	var authErr error
	for _, o := range ops {
		op, ok := o.(map[string]any)
		var res any
		var err error
		if ok {
			res, err = apply(c, op)
		} else {
			err = core.Errorf("each change must be an object")
		}
		var auth *core.AuthError
		if errors.As(err, &auth) && authErr == nil {
			authErr = err
		}
		if err != nil {
			results = append(results, Result{Error: err.Error()})
		} else {
			results = append(results, Result{OK: true, Result: res})
		}
	}
	if err := save(c); err != nil {
		return nil, err
	}
	if authErr != nil && !slices.ContainsFunc(results, func(r Result) bool { return r.OK }) {
		return nil, authErr
	}
	return results, nil
}

// findList is a list by global id or name (case ignored; a name in two
// accounts must be given by id).
func findList(c *Cache, want string) (List, error) {
	want = strings.TrimSpace(want)
	found := []List{}
	for _, l := range c.Lists {
		if l.ID == want {
			return l, nil
		}
		if strings.EqualFold(l.Name, want) {
			found = append(found, l)
		}
	}
	names := []string{}
	for _, a := range registry.List() {
		for _, l := range c.Lists {
			if l.Account == a.ID {
				names = append(names, l.Name)
			}
		}
	}
	switch {
	case len(found) == 1:
		return found[0], nil
	case len(found) > 1:
		return List{}, core.Errorf("'%s' is a list in several accounts: give its id", want)
	case want == "":
		return List{}, core.Errorf("which list? %s", strings.Join(names, ", "))
	}
	return List{}, core.Errorf("no list '%s': %s", want, strings.Join(names, ", "))
}

// defaultAccount is the account new things go to: the one asked for, else
// the first with tasks.
func defaultAccount(op map[string]any) (registry.Account, error) {
	if want, _ := op["account"].(string); strings.TrimSpace(want) != "" {
		a, err := registry.Get(want)
		if err == nil && !Supported(a) {
			err = core.Errorf("%s accounts have no tasks here", a.Provider)
		}
		return a, err
	}
	for _, a := range registry.List() {
		if Supported(a) {
			return a, nil
		}
	}
	return registry.Account{}, core.AuthErrorf("no account with tasks connected")
}

func apply(c *Cache, op map[string]any) (any, error) {
	kind, _ := op["op"].(string)
	if kind == "" {
		kind, _ = op["action"].(string)
	}
	if !slices.Contains(Ops, kind) {
		return nil, core.Errorf("unknown op '%s': %s", kind, strings.Join(Ops, ", "))
	}
	op = clone(op)
	listRef, _ := op["list"].(string)
	var account string
	switch kind {
	case "create_list":
		a, err := defaultAccount(op)
		if err != nil {
			return nil, err
		}
		account = a.ID
	case "create":
		if strings.TrimSpace(listRef) != "" {
			l, err := findList(c, listRef)
			if err != nil {
				return nil, err
			}
			account, op["list"] = l.Account, local(l.Account, l.ID)
		} else {
			a, err := defaultAccount(op)
			if err != nil {
				return nil, err
			}
			account = a.ID
		}
		if parent, _ := op["parent"].(string); parent != "" {
			if local(account, parent) == "" {
				return nil, core.Errorf("the parent task '%s' is in another account", parent)
			}
			op["parent"] = local(account, parent)
		}
	case "rename_list", "delete_list":
		l, err := findList(c, listRef)
		if err != nil {
			return nil, err
		}
		account, op["list"] = l.Account, local(l.Account, l.ID)
	default:
		want, _ := op["id"].(string)
		if want == "" {
			want, _ = op["task"].(string)
		}
		if strings.TrimSpace(want) == "" {
			return nil, core.Errorf("`id` is required (a task's id from list)")
		}
		if !slices.ContainsFunc(c.Tasks, func(t Task) bool { return t.ID == want }) {
			return nil, core.Errorf("no task '%s' (list or sync first)", want)
		}
		acc, id, err := registry.SplitID(want)
		if err != nil {
			return nil, err
		}
		account, op["id"] = acc, id
		delete(op, "task")
		if kind == "move" {
			l, err := findList(c, listRef)
			if err != nil {
				return nil, err
			}
			if l.Account != account {
				return nil, core.Errorf("tasks move between lists of the same account only")
			}
			op["list"] = local(account, l.ID)
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
	case Task:
		return globalTask(account, r), nil
	case List:
		r.ID, r.Account = registry.GlobalID(account, r.ID), account
		return r, nil
	case map[string]any:
		if id, ok := r["deleted"].(string); ok {
			r["deleted"] = registry.GlobalID(account, id)
		}
		return r, nil
	}
	return res, nil
}

func clone(m map[string]any) map[string]any {
	out := make(map[string]any, len(m))
	for k, v := range m {
		out[k] = v
	}
	return out
}

// -- reading ---------------------------------------------------------------

// Listing is what list answers.
type Listing struct {
	SyncedAt int64  `json:"syncedAt"`
	Lists    []List `json:"lists"`
	Tasks    []Task `json:"tasks"`
}

// ListTasks is the copy: one list's (by id or name) when given, one
// account's, the completed tasks only with done.
func ListTasks(list, account string, done bool) (*Listing, error) {
	c := Load()
	listID := ""
	if list != "" {
		l, err := findList(c, list)
		if err != nil {
			return nil, err
		}
		listID = l.ID
	}
	if account != "" {
		a, err := registry.Get(account)
		if err != nil {
			return nil, err
		}
		account = a.ID
	}
	out := []Task{}
	for _, t := range c.Tasks {
		if (listID == "" || t.ListID == listID) && (account == "" || t.Account == account) && (done || !t.Done) {
			out = append(out, t)
		}
	}
	return &Listing{SyncedAt: c.SyncedAt, Lists: c.Lists, Tasks: out}, nil
}

// Summary is the tasks part of status.
func Summary() map[string]any {
	c := Load()
	path, _ := core.StatePath(CacheFile)
	return map[string]any{"lists": len(c.Lists), "count": len(c.Tasks), "syncedAt": c.SyncedAt, "error": c.Error, "cache": path}
}

// AccountError is the account's last tasks sync failure.
func AccountError(account string) string {
	if m := Load().Accounts[account]; m != nil {
		return m.Error
	}
	return ""
}
