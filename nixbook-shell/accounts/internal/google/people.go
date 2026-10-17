package google

import (
	"errors"
	"net/url"
	"slices"
	"strings"
	"time"

	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/contacts"
	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/core"
	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/registry"
)

func peopleAPI() string {
	return core.Endpoint("NIXBOOK_ACCOUNTS_GOOGLE_PEOPLE_API", "https://people.googleapis.com/v1")
}

func init() {
	contacts.Register("google", func(a registry.Account) (contacts.Provider, error) {
		return &people{account: a}, nil
	}, nil)
}

// people is a Google account's contacts (People API): synced with its sync
// tokens, changed field by field.
type people struct {
	account registry.Account
	token   string
}

func (p *people) call(method, path string, body any, out any) error {
	if p.token == "" {
		t, err := AccessToken(p.account)
		if err != nil {
			return err
		}
		p.token = t
	}
	return core.Call(method, peopleAPI()+path, body, nil, p.token, out)
}

// resolveLabel is a label's id from its id or name; an unknown name makes a
// new label when create is set.
func (p *people) resolveLabel(sec *contacts.Section, want string, create bool) (string, error) {
	want = strings.TrimSpace(want)
	for _, l := range sec.Labels {
		if l.ID == want || contacts.Fold(l.Name) == contacts.Fold(want) {
			return l.ID, nil
		}
	}
	if !create || want == "" {
		return "", core.Errorf("no label '%s'", want)
	}
	var g obj
	if err := p.call("POST", "/contactGroups", obj{"contactGroup": obj{"name": want}}, &g); err != nil {
		return "", err
	}
	id := shortID(str(g, "resourceName"))
	name := str(g, "formattedName")
	if name == "" {
		name = want
	}
	sec.Labels = append(sec.Labels, contacts.Label{ID: id, Name: name})
	return id, nil
}

// -- sync ------------------------------------------------------------------

func (p *people) connections(syncToken string) ([]obj, string, error) {
	out, page, next := []obj{}, "", ""
	for {
		q := url.Values{"personFields": {personFields}, "pageSize": {"1000"}, "requestSyncToken": {"true"}}
		if syncToken != "" {
			q.Set("syncToken", syncToken)
		}
		if page != "" {
			q.Set("pageToken", page)
		}
		var r obj
		if err := p.call("GET", "/people/me/connections?"+q.Encode(), nil, &r); err != nil {
			return nil, "", err
		}
		out = append(out, list(r, "connections")...)
		if t := str(r, "nextSyncToken"); t != "" {
			next = t
		}
		if page = str(r, "nextPageToken"); page == "" {
			return out, next, nil
		}
	}
}

func (p *people) labels() ([]contacts.Label, error) {
	out, page := []contacts.Label{}, ""
	for {
		q := url.Values{"pageSize": {"1000"}, "groupFields": {"name,groupType,memberCount"}}
		if page != "" {
			q.Set("pageToken", page)
		}
		var r obj
		if err := p.call("GET", "/contactGroups?"+q.Encode(), nil, &r); err != nil {
			return nil, err
		}
		for _, g := range list(r, "contactGroups") {
			if str(g, "groupType") != "USER_CONTACT_GROUP" {
				continue
			}
			name := str(g, "formattedName")
			if name == "" {
				name = str(g, "name")
			}
			out = append(out, contacts.Label{ID: shortID(str(g, "resourceName")), Name: name, Count: num(g, "memberCount")})
		}
		if page = str(r, "nextPageToken"); page == "" {
			return out, nil
		}
	}
}

func expiredSyncToken(err error) bool {
	var api *core.APIError
	if !errors.As(err, &api) || (api.Status != 400 && api.Status != 410) {
		return false
	}
	text := strings.ToLower(strings.ReplaceAll(api.Message+" "+api.Reason, "_", " "))
	return strings.Contains(text, "sync token")
}

// Sync: the changes since the last sync token, everything when full or when
// Google's token (good for 7 days) has expired.
func (p *people) Sync(sec *contacts.Section, full bool) (int, bool, error) {
	start := sec.SyncToken
	if full {
		start = ""
	}
	persons, next, err := p.connections(start)
	if err != nil && start != "" && expiredSyncToken(err) {
		start = ""
		persons, next, err = p.connections("")
	}
	if err != nil {
		return 0, false, err
	}
	byID := map[string]contacts.Contact{}
	if start != "" {
		for _, c := range sec.Contacts {
			byID[c.ID] = c
		}
	}
	changed := 0
	for _, person := range persons {
		id := shortID(str(person, "resourceName"))
		meta, _ := person["metadata"].(obj)
		if deleted, _ := meta["deleted"].(bool); deleted {
			if _, ok := byID[id]; ok {
				delete(byID, id)
				changed++
			}
			continue
		}
		byID[id] = simplify(person)
		changed++
	}
	labels, err := p.labels()
	if err != nil {
		return 0, false, err
	}
	sec.Labels = labels
	sec.Contacts = make([]contacts.Contact, 0, len(byID))
	for _, c := range byID {
		sec.Contacts = append(sec.Contacts, c)
	}
	sec.SyncToken = next
	sec.SyncedAt = time.Now().UnixMilli()
	return changed, start == "", nil
}

// -- changes ---------------------------------------------------------------

func nonEmptyString(op obj, key string) (string, error) {
	v, _ := op[key].(string)
	if v = strings.TrimSpace(v); v == "" {
		return "", core.Errorf("`%s` is required", key)
	}
	return v, nil
}

// Apply runs one change on Google, its answer put in the section.
func (p *people) Apply(sec *contacts.Section, op obj) (any, error) {
	kind := str(op, "op")
	if kind == "" {
		kind = str(op, "action")
	}
	switch kind {
	case "create":
		fields, err := pickFields(op)
		if err != nil {
			return nil, err
		}
		named := false
		for _, k := range []string{"name", "givenName", "familyName", "emails", "phones", "organization"} {
			switch v := fields[k].(type) {
			case string:
				named = named || strings.TrimSpace(v) != ""
			case []any:
				named = named || len(v) > 0
			}
		}
		if !named {
			return nil, core.Errorf("a new contact needs a name, an email, a phone or a company")
		}
		body, _, err := p.buildFields(sec, fields, nil)
		if err != nil {
			return nil, err
		}
		var person obj
		if err := p.call("POST", "/people:createContact?personFields="+personFields, body, &person); err != nil {
			return nil, err
		}
		c := simplify(person)
		sec.Upsert(c)
		return c, nil
	case "create_label":
		name, err := nonEmptyString(op, "name")
		if err != nil {
			return nil, err
		}
		if _, err := p.resolveLabel(sec, name, false); err == nil {
			return nil, core.Errorf("there is already a label '%s'", name)
		}
		id, err := p.resolveLabel(sec, name, true)
		return contacts.Label{ID: id, Name: name}, err
	case "rename_label", "delete_label":
		id, err := p.resolveLabel(sec, str(op, "label"), false)
		if err != nil {
			return nil, err
		}
		if kind == "delete_label" {
			// The label only: its contacts stay.
			if err := p.call("DELETE", "/contactGroups/"+id+"?deleteContacts=false", nil, nil); err != nil {
				return nil, err
			}
			sec.Labels = slices.DeleteFunc(sec.Labels, func(l contacts.Label) bool { return l.ID == id })
			for i := range sec.Contacts {
				sec.Contacts[i].Labels = slices.DeleteFunc(sec.Contacts[i].Labels, func(l string) bool { return l == id })
			}
			return obj{"deleted": id}, nil
		}
		name, err := nonEmptyString(op, "name")
		if err != nil {
			return nil, err
		}
		var g obj
		if err := p.call("GET", "/contactGroups/"+id, nil, &g); err != nil {
			return nil, err
		}
		if err := p.call("PUT", "/contactGroups/"+id, obj{
			"contactGroup":      obj{"resourceName": "contactGroups/" + id, "etag": str(g, "etag"), "name": name},
			"updateGroupFields": "name",
		}, nil); err != nil {
			return nil, err
		}
		for i := range sec.Labels {
			if sec.Labels[i].ID == id {
				sec.Labels[i].Name = name
			}
		}
		return contacts.Label{ID: id, Name: name}, nil
	}

	c, ok := sec.Find(str(op, "id"))
	if !ok {
		return nil, core.Errorf("no contact '%s' (list or sync first)", str(op, "id"))
	}
	if kind == "delete" {
		if err := p.call("DELETE", "/people/"+c.ID+":deleteContact", nil, nil); err != nil {
			return nil, err
		}
		sec.Contacts = slices.DeleteFunc(sec.Contacts, func(x contacts.Contact) bool { return x.ID == c.ID })
		return obj{"deleted": c.ID, "name": c.Name}, nil
	}
	fields := obj{"starred": kind == "star"}
	if kind == "update" {
		var err error
		if fields, err = pickFields(op); err != nil {
			return nil, err
		}
		if len(fields) == 0 {
			return nil, core.Errorf("nothing to change: give the fields to set")
		}
	} else if kind != "star" && kind != "unstar" {
		return nil, core.Errorf("unknown op '%s'", kind)
	}
	// Google's current copy: its etag, and what the app doesn't edit kept.
	var raw obj
	if err := p.call("GET", "/people/"+c.ID+"?personFields="+personFields, nil, &raw); err != nil {
		return nil, err
	}
	body, mask, err := p.buildFields(sec, fields, raw)
	if err != nil {
		return nil, err
	}
	body["resourceName"], body["etag"] = raw["resourceName"], raw["etag"]
	q := url.Values{"updatePersonFields": {strings.Join(mask, ",")}, "personFields": {personFields}}
	var person obj
	if err := p.call("PATCH", "/people/"+c.ID+":updateContact?"+q.Encode(), body, &person); err != nil {
		return nil, err
	}
	c = simplify(person)
	sec.Upsert(c)
	return c, nil
}
