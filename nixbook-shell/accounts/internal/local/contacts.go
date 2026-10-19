package local

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/contacts"
	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/core"
	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/registry"
)

const contactsFile = "contacts.json"

func init() {
	contacts.Register("local", func(registry.Account) (contacts.Provider, error) { return localContacts{}, nil }, nil)
}

type contactsData struct {
	// Labels made but not on a contact yet (a label exists while used).
	Labels   []string           `json:"labels"`
	Contacts []contacts.Contact `json:"contacts"`
}

type localContacts struct{}

func loadContacts() (*contactsData, error) {
	d := &contactsData{}
	if _, err := read(contactsFile, d); err != nil {
		return nil, err
	}
	if d.Contacts == nil {
		d.Contacts = []contacts.Contact{}
	}
	return d, nil
}

// fill puts the data in the section (labels with their counts).
func fill(sec *contacts.Section, d *contactsData) {
	counts := map[string]int{}
	for _, l := range d.Labels {
		counts[l] = 0
	}
	for _, c := range d.Contacts {
		for _, l := range c.Labels {
			counts[l]++
		}
	}
	sec.Labels = []contacts.Label{}
	for name, n := range counts {
		sec.Labels = append(sec.Labels, contacts.Label{ID: name, Name: name, Count: n})
	}
	sec.Contacts = slices.Clone(d.Contacts)
	sec.SyncedAt = time.Now().UnixMilli()
}

// Sync reads the file.
func (localContacts) Sync(sec *contacts.Section, full bool) (int, bool, error) {
	d, err := loadContacts()
	if err != nil {
		return 0, false, err
	}
	changed := len(d.Contacts) - len(sec.Contacts)
	fill(sec, d)
	return max(changed, 0), true, nil
}

func typedList(v any, key string) ([]contacts.Typed, error) {
	raw, ok := v.([]any)
	if !ok && v != nil {
		raw = []any{v}
	}
	out := []contacts.Typed{}
	for _, r := range raw {
		switch x := r.(type) {
		case string:
			if x = strings.TrimSpace(x); x != "" {
				out = append(out, contacts.Typed{Value: x})
			}
		case map[string]any:
			v, _ := x["value"].(string)
			t, _ := x["type"].(string)
			if v = strings.TrimSpace(v); v != "" {
				out = append(out, contacts.Typed{Value: v, Type: t})
			}
		default:
			return nil, core.Errorf("`%s` must be a list of strings or {value, type}", key)
		}
	}
	return out, nil
}

func pad2(n int) string {
	if n < 10 {
		return "0" + strconv.Itoa(n)
	}
	return strconv.Itoa(n)
}

// applyContact sets the given fields on the contact.
func applyContact(c *contacts.Contact, op map[string]any) error {
	for _, f := range []struct {
		key string
		dst *string
	}{
		{"givenName", &c.GivenName},
		{"familyName", &c.FamilyName},
		{"nickname", &c.Nickname},
		{"organization", &c.Organization},
		{"title", &c.Title},
		{"notes", &c.Notes},
	} {
		v, has, err := str(op, f.key)
		if err != nil {
			return err
		}
		if has {
			*f.dst = strings.TrimSpace(v)
		}
	}
	if name, has, err := str(op, "name"); err != nil {
		return err
	} else if has && op["givenName"] == nil && op["familyName"] == nil {
		parts := strings.SplitN(strings.TrimSpace(name), " ", 2)
		c.GivenName, c.FamilyName = parts[0], ""
		if len(parts) > 1 {
			c.FamilyName = parts[1]
		}
	}
	c.Name = strings.TrimSpace(c.GivenName + " " + c.FamilyName)
	for _, f := range []struct {
		key string
		dst *[]contacts.Typed
	}{{"emails", &c.Emails}, {"phones", &c.Phones}, {"urls", &c.URLs}} {
		if v, has := op[f.key]; has {
			list, err := typedList(v, f.key)
			if err != nil {
				return err
			}
			*f.dst = list
		}
	}
	if v, has := op["addresses"]; has {
		raw, ok := v.([]any)
		if !ok && v != nil {
			raw = []any{v}
		}
		c.Addresses = []contacts.Address{}
		for _, r := range raw {
			a := contacts.Address{}
			switch x := r.(type) {
			case string:
				a.Street = strings.TrimSpace(x)
			case map[string]any:
				get := func(k string) string { s, _ := x[k].(string); return strings.TrimSpace(s) }
				a = contacts.Address{
					Type: get("type"), Street: get("street"), City: get("city"), Region: get("region"),
					PostalCode: get("postalCode"), Country: get("country"),
				}
				if a.Street == "" && a.City == "" && a.Region == "" && a.PostalCode == "" && a.Country == "" {
					a.Street = get("value")
				}
			default:
				return core.Errorf("`addresses` must be a list of strings or {street, city, …}")
			}
			parts := []string{}
			for _, p := range []string{a.Street, strings.TrimSpace(a.PostalCode + " " + a.City), a.Region, a.Country} {
				if p != "" {
					parts = append(parts, p)
				}
			}
			if len(parts) == 0 {
				continue
			}
			a.Value = strings.Join(parts, "\n")
			c.Addresses = append(c.Addresses, a)
		}
	}
	if b, has, err := str(op, "birthday"); err != nil {
		return err
	} else if has {
		b = strings.TrimSpace(b)
		m := contacts.BirthdayInput.FindStringSubmatch(b)
		switch {
		case b == "":
			c.Birthday = ""
		case m == nil:
			return core.Errorf("`birthday` must be YYYY-MM-DD or MM-DD")
		default:
			month, _ := strconv.Atoi(m[2])
			day, _ := strconv.Atoi(m[3])
			if month < 1 || month > 12 || day < 1 || day > 31 {
				return core.Errorf("`birthday` must be YYYY-MM-DD or MM-DD")
			}
			c.Birthday = "--" + pad2(month) + "-" + pad2(day)
			if m[1] != "" {
				c.Birthday = m[1] + c.Birthday[1:]
			}
		}
	}
	if v, has := op["labels"]; has {
		raw, ok := v.([]any)
		if s, isStr := v.(string); isStr {
			raw, ok = []any{s}, true
		}
		if !ok && v != nil {
			return core.Errorf("`labels` must be a list of label names")
		}
		c.Labels = []string{}
		for _, l := range raw {
			if s, ok := l.(string); ok && strings.TrimSpace(s) != "" && !slices.Contains(c.Labels, strings.TrimSpace(s)) {
				c.Labels = append(c.Labels, strings.TrimSpace(s))
			}
		}
	}
	if v, has := op["starred"]; has {
		b, ok := v.(bool)
		if !ok {
			return core.Errorf("`starred` must be true or false")
		}
		c.Starred = b
	}
	if c.Name == "" {
		c.Name = c.Organization
	}
	c.Updated = now()
	return nil
}

// savePhoto keeps a contact's photo in the data directory (photos/, named
// by its content: the app shows a new one, not its cached old one), the old
// one removed; its file:// URL, "" without data.
func savePhoto(c contacts.Contact, data []byte) (string, error) {
	removePhoto(c.Photo)
	if len(data) == 0 {
		return "", nil
	}
	dir, err := path("photos")
	if err != nil {
		return "", err
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	sum := sha256.Sum256(data)
	file := filepath.Join(dir, c.ID+"-"+hex.EncodeToString(sum[:4])+".jpg")
	if err := os.WriteFile(file, data, 0o600); err != nil {
		return "", err
	}
	return "file://" + file, nil
}

// removePhoto deletes a photo savePhoto kept (only from photos/).
func removePhoto(url string) {
	dir, err := path("photos")
	file := strings.TrimPrefix(url, "file://")
	if err == nil && file != url && filepath.Dir(file) == dir {
		_ = os.Remove(file)
	}
}

// Apply changes the file, then the section.
func (localContacts) Apply(sec *contacts.Section, op map[string]any) (any, error) {
	d, err := loadContacts()
	if err != nil {
		return nil, err
	}
	var res any
	switch kind := core.Kind(op); kind {
	case "create":
		c := contacts.Contact{
			ID: newID(), Emails: []contacts.Typed{}, Phones: []contacts.Typed{}, URLs: []contacts.Typed{},
			Addresses: []contacts.Address{}, Labels: []string{},
		}
		if err := applyContact(&c, op); err != nil {
			return nil, err
		}
		if c.Name == "" && len(c.Emails) == 0 && len(c.Phones) == 0 {
			return nil, core.Errorf("a new contact needs a name, an email, a phone or a company")
		}
		d.Contacts = append(d.Contacts, c)
		res = c
	case "create_label":
		name, _, _ := str(op, "name")
		if name = strings.TrimSpace(name); name == "" {
			return nil, core.Errorf("`name` is required")
		}
		if slices.ContainsFunc(sec.Labels, func(l contacts.Label) bool { return strings.EqualFold(l.Name, name) }) {
			return nil, core.Errorf("there is already a label '%s'", name)
		}
		d.Labels = append(d.Labels, name)
		res = contacts.Label{ID: name, Name: name}
	case "rename_label", "delete_label":
		label, _, _ := str(op, "label")
		name, _, _ := str(op, "name")
		if kind == "rename_label" && strings.TrimSpace(name) == "" {
			return nil, core.Errorf("`name` is required")
		}
		n := 0
		for i := range d.Contacts {
			if !slices.Contains(d.Contacts[i].Labels, label) {
				continue
			}
			n++
			d.Contacts[i].Labels = slices.DeleteFunc(d.Contacts[i].Labels, func(l string) bool { return l == label })
			if kind == "rename_label" {
				d.Contacts[i].Labels = append(d.Contacts[i].Labels, strings.TrimSpace(name))
			}
		}
		d.Labels = slices.DeleteFunc(d.Labels, func(l string) bool { return l == label })
		if kind == "delete_label" {
			res = map[string]any{"deleted": label, "contacts": n}
		} else {
			d.Labels = append(d.Labels, strings.TrimSpace(name))
			res = contacts.Label{ID: strings.TrimSpace(name), Name: strings.TrimSpace(name), Count: n}
		}
	default:
		id, _, _ := str(op, "id")
		i := slices.IndexFunc(d.Contacts, func(c contacts.Contact) bool { return c.ID == id })
		if i < 0 {
			return nil, core.Errorf("no contact '%s'", id)
		}
		switch kind {
		case "delete":
			res = map[string]any{"deleted": id, "name": d.Contacts[i].Name}
			removePhoto(d.Contacts[i].Photo)
			d.Contacts = slices.Delete(d.Contacts, i, i+1)
		case "set_photo":
			data, _ := op["photoBytes"].([]byte)
			photo, err := savePhoto(d.Contacts[i], data)
			if err != nil {
				return nil, err
			}
			d.Contacts[i].Photo, d.Contacts[i].Updated = photo, now()
			res = d.Contacts[i]
		case "star", "unstar":
			d.Contacts[i].Starred = kind == "star"
			d.Contacts[i].Updated = now()
			res = d.Contacts[i]
		case "update":
			if err := applyContact(&d.Contacts[i], op); err != nil {
				return nil, err
			}
			res = d.Contacts[i]
		default:
			return nil, core.Errorf("unknown op '%s'", kind)
		}
	}
	if err := write(contactsFile, d); err != nil {
		return nil, err
	}
	fill(sec, d)
	return res, nil
}
