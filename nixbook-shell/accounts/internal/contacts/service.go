package contacts

import (
	"regexp"
	"slices"
	"strings"

	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/core"
	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/registry"
)

// CacheFile is the local copy's name in the state directory.
const CacheFile = "contacts.json"

// MaxOps is the most changes one apply runs.
const MaxOps = 50

// Provider is one account's contacts at its provider.
type Provider interface {
	// Sync brings the provider's changes into the section (everything when
	// full, or when its sync state can't go on): how many contacts changed,
	// and whether it fetched everything.
	Sync(sec *Section, full bool) (changed int, fetchedAll bool, err error)
	// Apply runs one change (ops: create, update, delete, star, unstar,
	// set_photo, create_label, rename_label, delete_label), with the
	// provider's own ids; label references in "labels" are its label ids or
	// names (a new name makes a label); set_photo's "photoBytes" is the
	// JPEG (LoadPhoto), nil to remove the photo. It updates the section.
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
// given, says whether an account of that kind has contacts at all.
func Register(provider string, f Factory, has func(registry.Account) bool) {
	factories[provider] = entry{f, has}
}

// Supported says whether the account has contacts here.
func Supported(a registry.Account) bool {
	e, ok := factories[a.Provider]
	return ok && (e.has == nil || e.has(a))
}

func providerFor(a registry.Account) (Provider, error) {
	if !Supported(a) {
		return nil, core.Errorf("%s has no contacts here", a.Name)
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
	if c.Labels == nil {
		c.Labels = []Label{}
	}
	if c.Contacts == nil {
		c.Contacts = []Contact{}
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
	sortContacts(c.Contacts)
	slices.SortStableFunc(c.Labels, func(a, b Label) int { return strings.Compare(Fold(a.Name), Fold(b.Name)) })
	// For the shell: the stalest sync, the first failure.
	c.SyncedAt, c.Error = 0, ""
	for _, a := range registry.List() {
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
	return core.WriteJSON(CacheFile, c)
}

// section is the account's part of the copy, with the provider's own ids.
func section(c *Cache, account string) *Section {
	m := c.Accounts[account]
	if m == nil {
		m = &Meta{}
	}
	s := &Section{SyncToken: m.SyncToken, SyncedAt: m.SyncedAt, Error: m.Error, Labels: []Label{}, Contacts: []Contact{}}
	for _, l := range c.Labels {
		if l.Account == account {
			l.ID = registry.LocalID(account, l.ID)
			s.Labels = append(s.Labels, l)
		}
	}
	for _, x := range c.Contacts {
		if x.Account == account {
			s.Contacts = append(s.Contacts, toLocal(account, x))
		}
	}
	return s
}

func toLocal(account string, x Contact) Contact {
	x.ID = registry.LocalID(account, x.ID)
	labels := []string{}
	for _, l := range x.Labels {
		if id := registry.LocalID(account, l); id != "" {
			labels = append(labels, id)
		}
	}
	x.Labels = labels
	return x
}

func toGlobal(account string, x Contact) Contact {
	x.ID = registry.GlobalID(account, x.ID)
	x.Account = account
	labels := make([]string, 0, len(x.Labels))
	for _, l := range x.Labels {
		labels = append(labels, registry.GlobalID(account, l))
	}
	x.Labels = labels
	if x.Emails == nil {
		x.Emails = []Typed{}
	}
	if x.Phones == nil {
		x.Phones = []Typed{}
	}
	if x.URLs == nil {
		x.URLs = []Typed{}
	}
	if x.Addresses == nil {
		x.Addresses = []Address{}
	}
	return x
}

// put writes the section back into the copy, global ids.
func put(c *Cache, account string, s *Section) {
	c.Accounts[account] = &Meta{SyncToken: s.SyncToken, SyncedAt: s.SyncedAt, Error: s.Error}
	c.Labels = slices.DeleteFunc(c.Labels, func(l Label) bool { return l.Account == account })
	for _, l := range s.Labels {
		l.ID, l.Account = registry.GlobalID(account, l.ID), account
		c.Labels = append(c.Labels, l)
	}
	c.Contacts = slices.DeleteFunc(c.Contacts, func(x Contact) bool { return x.Account == account })
	for _, x := range s.Contacts {
		c.Contacts = append(c.Contacts, toGlobal(account, x))
	}
}

// Forget drops an account's contacts from the copy (it was removed); every
// account's with "".
func Forget(account string) error {
	unlock, err := core.Lock("contacts")
	if err != nil {
		return err
	}
	defer unlock()
	c := Load()
	if account == "" {
		c = &Cache{Accounts: map[string]*Meta{}, Labels: []Label{}, Contacts: []Contact{}}
	} else {
		put(c, account, &Section{})
		delete(c.Accounts, account)
	}
	if err := save(c); err != nil {
		return err
	}
	prunePhotos(c)
	return nil
}

// -- sync ------------------------------------------------------------------

// AccountSync is what a sync did for one account.
type AccountSync struct {
	Account string `json:"account"`
	Full    bool   `json:"full"`
	Changed int    `json:"changed"`
	Count   int    `json:"count"`
	Error   string `json:"error,omitempty"`
}

// SyncResult is what a sync did.
type SyncResult struct {
	Accounts []AccountSync `json:"accounts"`
	Count    int           `json:"count"`
	SyncedAt int64         `json:"syncedAt"`
}

// Sync brings each account's changes into the local copy (one account's
// with account set). A failing account keeps its contacts and its failure
// in the copy; it fails only when every account did (the first failure).
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
			return nil, core.AuthErrorf("no account with contacts connected")
		}
	}
	unlock, err := core.Lock("contacts")
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
		r.Count = len(s.Contacts)
		put(c, a.ID, s)
		res.Accounts = append(res.Accounts, r)
	}
	if err := save(c); err != nil {
		return nil, err
	}
	prunePhotos(c)
	res.Count, res.SyncedAt = len(c.Contacts), c.SyncedAt
	if failed == len(accounts) {
		return res, firstErr
	}
	return res, nil
}

// -- changes ---------------------------------------------------------------

// Ops are the changes apply takes, as {"op": …} (or "action").
var Ops = []string{"create", "update", "delete", "star", "unstar", "set_photo", "create_label", "rename_label", "delete_label"}

// Result is one change's outcome.
type Result = core.Result

// Apply runs {op…} or {ops: […]}, in order, each on its own, each at its
// account's provider.
func Apply(request any) ([]Result, error) {
	ops, err := core.Ops(request, MaxOps)
	if err != nil {
		return nil, err
	}
	unlock, err := core.Lock("contacts")
	if err != nil {
		return nil, err
	}
	defer unlock()
	c := Load()
	results, authErr := core.RunOps(ops, func(op map[string]any) (any, error) { return apply(c, op) })
	if err := save(c); err != nil {
		return nil, err
	}
	// Every change refused for want of a sign-in: say so (exit 2).
	if authErr != nil {
		return nil, authErr
	}
	return results, nil
}

// targetAccount is the account a new contact or label goes to: the one
// asked for (id, name or email), else the first with contacts.
func targetAccount(op map[string]any) (registry.Account, error) {
	if want, _ := op["account"].(string); strings.TrimSpace(want) != "" {
		a, err := registry.Get(want)
		if err != nil {
			return a, err
		}
		if !Supported(a) {
			return a, core.Errorf("%s accounts have no contacts here", a.Provider)
		}
		return a, nil
	}
	for _, a := range registry.List() {
		if Supported(a) {
			return a, nil
		}
	}
	return registry.Account{}, core.AuthErrorf("no account with contacts connected")
}

// labelAccount finds the label (global id, or a name in one account).
func labelAccount(c *Cache, want string) (string, string, error) {
	want = strings.TrimSpace(want)
	matches := []Label{}
	for _, l := range c.Labels {
		if l.ID == want || Fold(l.Name) == Fold(want) {
			matches = append(matches, l)
		}
	}
	switch {
	case len(matches) == 0:
		return "", "", core.Errorf("no label '%s'", want)
	case len(matches) > 1 && matches[0].ID != want:
		return "", "", core.Errorf("'%s' is a label in several accounts: give its id", want)
	}
	return matches[0].Account, registry.LocalID(matches[0].Account, matches[0].ID), nil
}

func apply(c *Cache, op map[string]any) (any, error) {
	kind := core.Kind(op)
	if !slices.Contains(Ops, kind) {
		return nil, core.Errorf("unknown op '%s': %s", kind, strings.Join(Ops, ", "))
	}
	var account string
	switch kind {
	case "create", "create_label":
		a, err := targetAccount(op)
		if err != nil {
			return nil, err
		}
		account = a.ID
	case "rename_label", "delete_label":
		want, _ := op["label"].(string)
		acc, id, err := labelAccount(c, want)
		if err != nil {
			return nil, err
		}
		account = acc
		op = core.Clone(op)
		op["label"] = id
	default:
		want, _ := op["id"].(string)
		if want == "" {
			want, _ = op["contact"].(string)
		}
		if strings.TrimSpace(want) == "" {
			return nil, core.Errorf("`id` is required (a contact's id from list)")
		}
		if !slices.ContainsFunc(c.Contacts, func(x Contact) bool { return x.ID == want }) {
			return nil, core.Errorf("no contact '%s' (list or sync first)", want)
		}
		acc, id, err := registry.SplitID(want)
		if err != nil {
			return nil, err
		}
		account = acc
		op = core.Clone(op)
		op["id"] = id
		delete(op, "contact")
	}
	if kind == "set_photo" {
		var data []byte
		if path, _ := op["photo"].(string); strings.TrimSpace(path) != "" {
			var err error
			if data, err = LoadPhoto(strings.TrimSpace(path)); err != nil {
				return nil, err
			}
		}
		op["photoBytes"] = data
		delete(op, "photo")
	}
	// Labels given by global id: this account's, as its own ids.
	if raw, ok := op["labels"]; ok {
		list, isList := raw.([]any)
		if s, isStr := raw.(string); isStr {
			list, isList = []any{s}, true
		}
		if isList {
			out := []any{}
			for _, l := range list {
				name, _ := l.(string)
				// A label id (an account's prefix): this account's, known.
				if acc, id, err := registry.SplitID(name); err == nil && slices.ContainsFunc(registry.List(), func(a registry.Account) bool { return a.ID == acc }) {
					if !slices.ContainsFunc(c.Labels, func(x Label) bool { return x.ID == name }) {
						return nil, core.Errorf("no label '%s'", name)
					}
					if acc != account {
						return nil, core.Errorf("the label '%s' is in another account", name)
					}
					name = id
				}
				out = append(out, name)
			}
			op = core.Clone(op)
			op["labels"] = out
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
	case Contact:
		return toGlobal(account, r), nil
	case Label:
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

// -- reading ---------------------------------------------------------------

var nonDigits = regexp.MustCompile(`\D`)

func matches(c Contact, words []string, cache *Cache) bool {
	parts := []string{c.Name, c.Nickname, c.Organization, c.Title, c.Notes}
	for _, e := range c.Emails {
		parts = append(parts, e.Value)
	}
	for _, a := range c.Addresses {
		parts = append(parts, a.Value)
	}
	parts = append(parts, labelNames(cache, c.Labels)...)
	hay := Fold(strings.Join(parts, " "))
	digits := ""
	for _, p := range c.Phones {
		digits += nonDigits.ReplaceAllString(p.Value, "") + " "
	}
	for _, w := range words {
		if strings.Contains(hay, Fold(w)) {
			continue
		}
		// A phone number as typed: its digits, when the word is mostly digits.
		d := nonDigits.ReplaceAllString(w, "")
		if len(d) >= 3 && len(d) >= len(w)-3 && strings.Contains(digits, d) {
			continue
		}
		return false
	}
	return true
}

// Listing is what list answers.
type Listing struct {
	SyncedAt int64     `json:"syncedAt"`
	Total    int       `json:"total"`
	Labels   []Label   `json:"labels"`
	Contacts []Contact `json:"contacts"`
}

// List searches the local copy: every word of query (accents and case
// ignored; phone numbers by their digits), a label (id or name), an
// account, starred only.
func List(query, label, account string, starred bool, limit int) (*Listing, error) {
	cache := Load()
	labelIDs := []string{}
	if label != "" {
		for _, l := range cache.Labels {
			if l.ID == label || Fold(l.Name) == Fold(label) {
				labelIDs = append(labelIDs, l.ID)
			}
		}
		if len(labelIDs) == 0 {
			return nil, core.Errorf("no label '%s'", label)
		}
	}
	if account != "" {
		a, err := registry.Get(account)
		if err != nil {
			return nil, err
		}
		account = a.ID
	}
	words := strings.Fields(query)
	out := []Contact{}
	for _, c := range cache.Contacts {
		if (len(labelIDs) == 0 || slices.ContainsFunc(c.Labels, func(l string) bool { return slices.Contains(labelIDs, l) })) &&
			(account == "" || c.Account == account) && (!starred || c.Starred) && matches(c, words, cache) {
			out = append(out, c)
		}
	}
	total := len(out)
	if limit > 0 && len(out) > limit {
		out = out[:limit]
	}
	for i := range out {
		out[i].Labels = labelNames(cache, out[i].Labels)
	}
	return &Listing{SyncedAt: cache.SyncedAt, Total: total, Labels: cache.Labels, Contacts: out}, nil
}

// Get is one contact, with its labels' names.
func Get(id string) (Contact, error) {
	cache := Load()
	for _, c := range cache.Contacts {
		if c.ID == strings.TrimSpace(id) {
			c.Labels = labelNames(cache, c.Labels)
			return c, nil
		}
	}
	return Contact{}, core.Errorf("no contact '%s' (list or sync first)", id)
}

// Summary is the contacts part of status, from the copy (Load).
func (c *Cache) Summary() map[string]any {
	path, _ := core.StatePath(CacheFile)
	return map[string]any{"count": len(c.Contacts), "syncedAt": c.SyncedAt, "error": c.Error, "cache": path}
}

// AccountError is the account's last contacts sync failure.
func (c *Cache) AccountError(account string) string {
	if m := c.Accounts[account]; m != nil {
		return m.Error
	}
	return ""
}
