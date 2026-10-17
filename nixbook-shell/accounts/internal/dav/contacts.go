package dav

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"path"
	"regexp"
	"slices"
	"strings"
	"time"

	"github.com/emersion/go-vcard"
	"github.com/emersion/go-webdav/carddav"

	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/contacts"
	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/core"
	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/registry"
)

func init() {
	contacts.Register("dav", func(a registry.Account) (contacts.Provider, error) {
		return &cards{account: a}, nil
	}, func(a registry.Account) bool { return a.ContactsHome != "" })
}

func randomBits() uint64 {
	var b [8]byte
	_, _ = rand.Read(b[:])
	return binary.LittleEndian.Uint64(b[:])
}

// starredCategory marks a starred contact (vCard has no star): a category,
// shown as the star, not as a label.
const starredCategory = "Starred"

// cards is a DAV account's contacts: every address book's (CardDAV), each
// synced with its sync token when the server has them (sync-collection),
// else read whole. A contact's id is its path on the server; labels are
// vCard categories (a label's id is its name).
type cards struct {
	account registry.Account
	client  *carddav.Client
}

func (p *cards) cc() (*carddav.Client, error) {
	if p.client == nil {
		c, err := cardClient(p.account)
		if err != nil {
			return nil, err
		}
		p.client = c
	}
	return p.client, nil
}

// syncState is the section's SyncToken: each address book's sync token.
type syncState map[string]string

func loadState(s string) syncState {
	st := syncState{}
	_ = json.Unmarshal([]byte(s), &st)
	return st
}

func (s syncState) String() string {
	b, _ := json.Marshal(s)
	return string(b)
}

// -- vCard <-> contact -----------------------------------------------------

var phoneTypes = map[string]string{"cell": "mobile", "home": "home", "work": "work", "fax": "homeFax", "pager": "pager", "main": "main"}

// typeOf is the app's type from a vCard field's TYPE params.
func typeOf(f *vcard.Field, known map[string]string) string {
	types := f.Params.Types()
	if f.Group != "" {
		// Apple keeps its own labels next to the field: "item1.X-ABLabel".
		return ""
	}
	for _, t := range types {
		t = strings.ToLower(t)
		if known != nil {
			if v, ok := known[t]; ok {
				return v
			}
		}
		if t == "home" || t == "work" || t == "other" {
			return t
		}
	}
	return ""
}

func typed(card vcard.Card, key string, known map[string]string) []contacts.Typed {
	out := []contacts.Typed{}
	for _, f := range card[key] {
		v := strings.TrimSpace(f.Value)
		if key == vcard.FieldTelephone || key == vcard.FieldEmail {
			v = strings.TrimPrefix(strings.TrimPrefix(v, "tel:"), "mailto:")
		}
		if v != "" {
			out = append(out, contacts.Typed{Value: v, Type: typeOf(f, known)})
		}
	}
	return out
}

var (
	bdayCompact = regexp.MustCompile(`^(\d{4}|--)(\d{2})(\d{2})`)
	bdayDashed  = regexp.MustCompile(`^(\d{4}|-)-?(\d{2})-(\d{2})`)
)

// birthday is BDAY as YYYY-MM-DD or --MM-DD (Apple's year 1604: none).
func birthday(v string) string {
	v = strings.TrimSpace(v)
	m := bdayDashed.FindStringSubmatch(v)
	if m == nil {
		m = bdayCompact.FindStringSubmatch(v)
	}
	if m == nil {
		return ""
	}
	if len(m[1]) == 4 && m[1] != "1604" {
		return m[1] + "-" + m[2] + "-" + m[3]
	}
	return "--" + m[2] + "-" + m[3]
}

func fromCard(id string, card vcard.Card) contacts.Contact {
	c := contacts.Contact{
		ID: id, Name: card.PreferredValue(vcard.FieldFormattedName), Nickname: card.PreferredValue(vcard.FieldNickname),
		Emails: typed(card, vcard.FieldEmail, nil), Phones: typed(card, vcard.FieldTelephone, phoneTypes),
		URLs: typed(card, vcard.FieldURL, nil), Title: card.PreferredValue(vcard.FieldTitle),
		Notes: card.PreferredValue(vcard.FieldNote), Birthday: birthday(card.PreferredValue(vcard.FieldBirthday)),
		Addresses: []contacts.Address{}, Labels: []string{},
	}
	if n := card.Name(); n != nil {
		c.GivenName, c.FamilyName = n.GivenName, n.FamilyName
		if c.Name == "" {
			c.Name = strings.TrimSpace(n.GivenName + " " + n.FamilyName)
		}
	}
	// ORG: "company;department".
	c.Organization = strings.SplitN(card.PreferredValue(vcard.FieldOrganization), ";", 2)[0]
	for _, a := range card.Addresses() {
		city := strings.TrimSpace(a.PostalCode + " " + a.Locality)
		parts := []string{}
		for _, x := range []string{a.StreetAddress, a.ExtendedAddress, city, a.Region, a.Country} {
			if x = strings.TrimSpace(x); x != "" {
				parts = append(parts, x)
			}
		}
		if len(parts) == 0 {
			continue
		}
		c.Addresses = append(c.Addresses, contacts.Address{
			Value: strings.Join(parts, "\n"), Type: typeOf(a.Field, nil), Street: a.StreetAddress, City: a.Locality,
			Region: a.Region, PostalCode: a.PostalCode, Country: a.Country,
		})
	}
	// A link as it is; an inline photo as a file, not in the copy.
	if f := card.Preferred(vcard.FieldPhoto); f != nil && strings.HasPrefix(f.Value, "http") {
		c.Photo = f.Value
	} else if f != nil {
		c.Photo = inlinePhoto(f)
	}
	for _, cat := range card.Categories() {
		cat = strings.TrimSpace(cat)
		switch {
		case cat == "":
		case strings.EqualFold(cat, starredCategory):
			c.Starred = true
		default:
			c.Labels = append(c.Labels, cat)
		}
	}
	if rev, err := card.Revision(); err == nil {
		c.Updated = rev.UTC().Format(time.RFC3339)
	}
	if c.Name == "" {
		c.Name = c.Organization
	}
	return c
}

// inlinePhoto is an inline PHOTO (vCard 4's data: URI, vCard 3's
// ENCODING=b) kept as a file: its URL, "" when it isn't one.
func inlinePhoto(f *vcard.Field) string {
	value, mime := f.Value, strings.ToLower(f.Params.Get(vcard.ParamType))
	if rest, ok := strings.CutPrefix(value, "data:"); ok {
		head, body, found := strings.Cut(rest, ",")
		if !found || !strings.HasSuffix(head, ";base64") {
			return ""
		}
		value, mime = body, strings.TrimSuffix(head, ";base64")
	} else if enc := strings.ToLower(f.Params.Get("ENCODING")); enc != "b" && enc != "base64" {
		return ""
	}
	data, err := base64.StdEncoding.DecodeString(strings.Join(strings.Fields(value), ""))
	if err != nil || len(data) == 0 {
		return ""
	}
	ext := ".jpg"
	switch {
	case strings.Contains(mime, "png"):
		ext = ".png"
	case strings.Contains(mime, "gif"):
		ext = ".gif"
	}
	url, err := contacts.PhotoFile(data, ext)
	if err != nil {
		return ""
	}
	return url
}

// setPhoto puts the JPEG inline in the card, in its version's way (none
// without data).
func setPhoto(card vcard.Card, data []byte) {
	delete(card, vcard.FieldPhoto)
	if len(data) == 0 {
		return
	}
	b64 := base64.StdEncoding.EncodeToString(data)
	if strings.HasPrefix(card.Value(vcard.FieldVersion), "4") {
		card.Set(vcard.FieldPhoto, &vcard.Field{Value: "data:image/jpeg;base64," + b64})
		return
	}
	card.Set(vcard.FieldPhoto, &vcard.Field{Value: b64, Params: vcard.Params{"ENCODING": {"b"}, vcard.ParamType: {"JPEG"}}})
}

// labelsOf is the labels in use, with their counts (a label exists while
// a contact has it).
func labelsOf(cs []contacts.Contact) []contacts.Label {
	counts := map[string]int{}
	for _, c := range cs {
		for _, l := range c.Labels {
			counts[l]++
		}
	}
	out := []contacts.Label{}
	for name, n := range counts {
		out = append(out, contacts.Label{ID: name, Name: name, Count: n})
	}
	return out
}

// -- sync ------------------------------------------------------------------

// Sync: each address book's changes since its sync token (sync-collection),
// everything for a new one, when full or when the server has no sync.
func (p *cards) Sync(sec *contacts.Section, full bool) (int, bool, error) {
	cc, err := p.cc()
	if err != nil {
		return 0, false, err
	}
	c, cancel := ctx()
	defer cancel()
	books, err := cc.FindAddressBooks(c, p.account.ContactsHome)
	if err != nil {
		return 0, false, asError(p.account, err)
	}
	old := loadState(sec.SyncToken)
	state := syncState{}
	byBook := map[string]map[string]contacts.Contact{}
	for _, x := range sec.Contacts {
		book := path.Dir(x.ID) + "/"
		if byBook[book] == nil {
			byBook[book] = map[string]contacts.Contact{}
		}
		byBook[book][x.ID] = x
	}
	all, changed, fetchedAll := []contacts.Contact{}, 0, true
	for _, b := range books {
		book := strings.TrimRight(b.Path, "/") + "/"
		current := byBook[book]
		if current == nil {
			current = map[string]contacts.Contact{}
		}
		token, known := old[book]
		var paths []string
		incremental := false
		if !full && known && token != "" {
			if r, err := cc.SyncCollection(c, book, &carddav.SyncQuery{SyncToken: token}); err == nil {
				incremental = true
				fetchedAll = false
				for _, d := range r.Deleted {
					if _, ok := current[d]; ok {
						delete(current, d)
						changed++
					}
				}
				for _, o := range r.Updated {
					paths = append(paths, o.Path)
				}
				state[book] = r.SyncToken
			}
		}
		if !incremental {
			// Everything: its sync token (when the server has them), then
			// every card.
			current = map[string]contacts.Contact{}
			if r, err := cc.SyncCollection(c, book, &carddav.SyncQuery{}); err == nil {
				state[book] = r.SyncToken
			}
			objs, err := cc.QueryAddressBook(c, book, &carddav.AddressBookQuery{DataRequest: carddav.AddressDataRequest{AllProp: true}})
			if err != nil {
				return 0, false, asError(p.account, err)
			}
			for _, o := range objs {
				current[o.Path] = fromCard(o.Path, o.Card)
				changed++
			}
		}
		if len(paths) > 0 {
			objs, err := cc.MultiGetAddressBook(c, book, &carddav.AddressBookMultiGet{Paths: paths, DataRequest: carddav.AddressDataRequest{AllProp: true}})
			if err != nil {
				return 0, false, asError(p.account, err)
			}
			for _, o := range objs {
				current[o.Path] = fromCard(o.Path, o.Card)
				changed++
			}
		}
		for _, x := range current {
			all = append(all, x)
		}
	}
	sec.Contacts = all
	sec.Labels = labelsOf(all)
	sec.SyncToken = state.String()
	sec.SyncedAt = time.Now().UnixMilli()
	return changed, fetchedAll, nil
}

// -- changes ---------------------------------------------------------------

func strField(op map[string]any, key string) (string, bool) {
	v, has := op[key]
	if !has {
		return "", false
	}
	s, _ := v.(string)
	return s, true
}

// listField is a list of {value, type, …} from strings or objects.
func listField(op map[string]any, key string) ([]map[string]any, bool, error) {
	v, has := op[key]
	if !has {
		return nil, false, nil
	}
	raw, ok := v.([]any)
	if !ok && v != nil {
		raw = []any{v}
	}
	out := []map[string]any{}
	for _, r := range raw {
		switch x := r.(type) {
		case string:
			if strings.TrimSpace(x) != "" {
				out = append(out, map[string]any{"value": strings.TrimSpace(x)})
			}
		case map[string]any:
			out = append(out, x)
		default:
			return nil, true, core.Errorf("`%s` must be a list of strings or {value, type}", key)
		}
	}
	return out, true, nil
}

func str(m map[string]any, key string) string {
	s, _ := m[key].(string)
	return strings.TrimSpace(s)
}

var vcardTypes = map[string]string{
	"mobile": "cell", "home": "home", "work": "work", "other": "other",
	"main": "main", "homeFax": "fax", "workFax": "fax", "pager": "pager", "workMobile": "cell",
}

// setTyped replaces a card's fields of that key, keeping the existing
// field (its params, its group) of an unchanged value.
func setTyped(card vcard.Card, key string, items []map[string]any) {
	old := card[key]
	fields := []*vcard.Field{}
	for _, it := range items {
		v := str(it, "value")
		if v == "" {
			continue
		}
		var f *vcard.Field
		for _, o := range old {
			if contacts.Normalize(strings.TrimPrefix(strings.TrimPrefix(o.Value, "tel:"), "mailto:")) == contacts.Normalize(v) {
				f = o
				break
			}
		}
		if f == nil {
			f = &vcard.Field{Value: v, Params: vcard.Params{}}
		}
		if t := str(it, "type"); t != "" {
			if vt, ok := vcardTypes[t]; ok {
				t = vt
			}
			params := vcard.Params{}
			for k, vs := range f.Params {
				if !strings.EqualFold(k, vcard.ParamType) {
					params[k] = vs
				}
			}
			params.Set(vcard.ParamType, t)
			f.Params = params
		}
		fields = append(fields, f)
	}
	if len(fields) == 0 {
		delete(card, key)
	} else {
		card[key] = fields
	}
}

// apply sets the given fields on the card (a new or Google-style patch:
// those absent stay).
func apply(card vcard.Card, op map[string]any, categories []string) error {
	given, hasGiven := strField(op, "givenName")
	family, hasFamily := strField(op, "familyName")
	full, hasFull := strField(op, "name")
	if hasGiven || hasFamily || hasFull {
		n := card.Name()
		if n == nil {
			n = &vcard.Name{}
		}
		if hasFull && !hasGiven && !hasFamily {
			parts := strings.SplitN(strings.TrimSpace(full), " ", 2)
			given, family = parts[0], ""
			if len(parts) > 1 {
				family = parts[1]
			}
		} else {
			if !hasGiven {
				given = n.GivenName
			}
			if !hasFamily {
				family = n.FamilyName
			}
		}
		n.GivenName, n.FamilyName = strings.TrimSpace(given), strings.TrimSpace(family)
		card.SetName(n)
		fn := strings.TrimSpace(n.GivenName + " " + n.FamilyName)
		if hasFull && !hasGiven && !hasFamily {
			fn = strings.TrimSpace(full)
		}
		card.SetValue(vcard.FieldFormattedName, fn)
	}
	for _, f := range [][2]string{{"nickname", vcard.FieldNickname}, {"title", vcard.FieldTitle}, {"notes", vcard.FieldNote}} {
		if v, has := strField(op, f[0]); has {
			if v = strings.TrimSpace(v); v == "" {
				delete(card, f[1])
			} else {
				card.SetValue(f[1], v)
			}
		}
	}
	if v, has := strField(op, "organization"); has {
		if v = strings.TrimSpace(v); v == "" {
			delete(card, vcard.FieldOrganization)
		} else {
			card.SetValue(vcard.FieldOrganization, v)
		}
	}
	if v, has := strField(op, "birthday"); has {
		v = strings.TrimSpace(v)
		switch m := regexp.MustCompile(`^(?:(\d{4})|-?-?)-?(\d{1,2})-(\d{1,2})$`).FindStringSubmatch(v); {
		case v == "":
			delete(card, vcard.FieldBirthday)
		case m == nil:
			return core.Errorf("`birthday` must be YYYY-MM-DD or MM-DD")
		case m[1] != "":
			card.SetValue(vcard.FieldBirthday, m[1]+"-"+pad2(m[2])+"-"+pad2(m[3]))
		default:
			card.SetValue(vcard.FieldBirthday, "--"+pad2(m[2])+pad2(m[3]))
		}
	}
	for _, f := range [][2]string{{"emails", vcard.FieldEmail}, {"phones", vcard.FieldTelephone}, {"urls", vcard.FieldURL}} {
		items, has, err := listField(op, f[0])
		if err != nil {
			return err
		}
		if has {
			setTyped(card, f[1], items)
		}
	}
	if items, has, err := listField(op, "addresses"); err != nil {
		return err
	} else if has {
		delete(card, vcard.FieldAddress)
		for _, it := range items {
			a := &vcard.Address{
				Field: &vcard.Field{Params: vcard.Params{}}, StreetAddress: str(it, "street"),
				Locality: str(it, "city"), Region: str(it, "region"), PostalCode: str(it, "postalCode"), Country: str(it, "country"),
			}
			if a.StreetAddress == "" && a.Locality == "" && a.Region == "" && a.PostalCode == "" && a.Country == "" {
				a.StreetAddress = str(it, "value")
			}
			if a.StreetAddress == "" && a.Locality == "" && a.Region == "" && a.PostalCode == "" && a.Country == "" {
				continue
			}
			if t := str(it, "type"); t != "" {
				a.Params.Set(vcard.ParamType, t)
			}
			card.AddAddress(a)
		}
	}
	if categories != nil {
		if len(categories) == 0 {
			delete(card, vcard.FieldCategories)
		} else {
			card.SetCategories(categories)
		}
	}
	card.SetRevision(time.Now())
	return nil
}

func pad2(s string) string {
	if len(s) == 1 {
		return "0" + s
	}
	return s
}

// categoriesFor is the card's categories after the change: its labels
// (given, or as they are) and the star.
func categoriesFor(current contacts.Contact, op map[string]any) ([]string, bool, error) {
	_, hasLabels := op["labels"]
	_, hasStar := op["starred"]
	if !hasLabels && !hasStar {
		return nil, false, nil
	}
	labels := current.Labels
	if hasLabels {
		labels = []string{}
		raw, _ := op["labels"].([]any)
		if s, ok := op["labels"].(string); ok {
			raw = []any{s}
		}
		for _, l := range raw {
			if s, ok := l.(string); ok && strings.TrimSpace(s) != "" && !slices.Contains(labels, strings.TrimSpace(s)) {
				labels = append(labels, strings.TrimSpace(s))
			}
		}
	}
	starred := current.Starred
	if hasStar {
		b, ok := op["starred"].(bool)
		if !ok {
			return nil, true, core.Errorf("`starred` must be true or false")
		}
		starred = b
	}
	out := slices.Clone(labels)
	if starred {
		out = append(out, starredCategory)
	}
	return out, true, nil
}

// put writes the card back and reads the server's copy (its path, its
// normalization).
func (p *cards) put(sec *contacts.Section, path string, card vcard.Card) (contacts.Contact, error) {
	cc, err := p.cc()
	if err != nil {
		return contacts.Contact{}, err
	}
	c, cancel := ctx()
	defer cancel()
	if card.Value(vcard.FieldVersion) == "" {
		card.SetValue(vcard.FieldVersion, "3.0")
	}
	if _, err := cc.PutAddressObject(c, path, card); err != nil {
		return contacts.Contact{}, asError(p.account, err)
	}
	x := fromCard(path, card)
	if o, err := cc.GetAddressObject(c, path); err == nil {
		x = fromCard(path, o.Card)
	}
	sec.Upsert(x)
	sec.Labels = labelsOf(sec.Contacts)
	return x, nil
}

// Apply runs one change on the server, its answer put in the section.
func (p *cards) Apply(sec *contacts.Section, op map[string]any) (any, error) {
	kind, _ := op["op"].(string)
	if kind == "" {
		kind, _ = op["action"].(string)
	}
	cc, err := p.cc()
	if err != nil {
		return nil, err
	}
	c, cancel := ctx()
	defer cancel()
	switch kind {
	case "create":
		named := false
		for _, k := range []string{"name", "givenName", "familyName", "organization"} {
			v, _ := strField(op, k)
			named = named || strings.TrimSpace(v) != ""
		}
		for _, k := range []string{"emails", "phones"} {
			items, _, _ := listField(op, k)
			named = named || len(items) > 0
		}
		if !named {
			return nil, core.Errorf("a new contact needs a name, an email, a phone or a company")
		}
		books, err := cc.FindAddressBooks(c, p.account.ContactsHome)
		if err != nil {
			return nil, asError(p.account, err)
		}
		if len(books) == 0 {
			return nil, core.Errorf("%s has no address book", p.account.Name)
		}
		uid := newUID()
		card := vcard.Card{}
		card.SetValue(vcard.FieldVersion, "3.0")
		card.SetValue(vcard.FieldUID, uid)
		cats, _, err := categoriesFor(contacts.Contact{}, op)
		if err != nil {
			return nil, err
		}
		if err := apply(card, op, cats); err != nil {
			return nil, err
		}
		if card.Value(vcard.FieldFormattedName) == "" {
			card.SetValue(vcard.FieldFormattedName, firstNonEmpty(card.Value(vcard.FieldOrganization), card.Value(vcard.FieldEmail), card.Value(vcard.FieldTelephone)))
		}
		if card.Name() == nil {
			card.SetName(&vcard.Name{})
		}
		return p.put(sec, strings.TrimRight(books[0].Path, "/")+"/"+uid+".vcf", card)
	case "create_label":
		name, _ := strField(op, "name")
		if name = strings.TrimSpace(name); name == "" {
			return nil, core.Errorf("`name` is required")
		}
		if slices.ContainsFunc(sec.Labels, func(l contacts.Label) bool { return strings.EqualFold(l.Name, name) }) {
			return nil, core.Errorf("there is already a label '%s'", name)
		}
		// A category exists while a contact has it: this one shows until
		// the next sync, or until a contact gets it.
		l := contacts.Label{ID: name, Name: name}
		sec.Labels = append(sec.Labels, l)
		return l, nil
	case "rename_label", "delete_label":
		want, _ := strField(op, "label")
		name, _ := strField(op, "name")
		if kind == "rename_label" && strings.TrimSpace(name) == "" {
			return nil, core.Errorf("`name` is required")
		}
		changed := 0
		for _, x := range slices.Clone(sec.Contacts) {
			if !slices.Contains(x.Labels, want) {
				continue
			}
			o, err := cc.GetAddressObject(c, x.ID)
			if err != nil {
				return nil, asError(p.account, err)
			}
			cats := []string{}
			for _, cat := range o.Card.Categories() {
				switch {
				case cat != want:
					cats = append(cats, cat)
				case kind == "rename_label":
					cats = append(cats, strings.TrimSpace(name))
				}
			}
			card := o.Card
			if len(cats) == 0 {
				delete(card, vcard.FieldCategories)
			} else {
				card.SetCategories(cats)
			}
			if _, err := p.put(sec, x.ID, card); err != nil {
				return nil, err
			}
			changed++
		}
		if kind == "delete_label" {
			sec.Labels = slices.DeleteFunc(sec.Labels, func(l contacts.Label) bool { return l.ID == want })
			return map[string]any{"deleted": want, "contacts": changed}, nil
		}
		sec.Labels = slices.DeleteFunc(sec.Labels, func(l contacts.Label) bool { return l.ID == want })
		sec.Labels = labelsOf(sec.Contacts)
		return contacts.Label{ID: strings.TrimSpace(name), Name: strings.TrimSpace(name), Count: changed}, nil
	}

	id, _ := strField(op, "id")
	current, ok := sec.Find(id)
	if !ok {
		return nil, core.Errorf("no contact '%s' (list or sync first)", id)
	}
	if kind == "delete" {
		if err := cc.RemoveAll(c, id); err != nil {
			return nil, asError(p.account, err)
		}
		sec.Contacts = slices.DeleteFunc(sec.Contacts, func(x contacts.Contact) bool { return x.ID == id })
		sec.Labels = labelsOf(sec.Contacts)
		return map[string]any{"deleted": id, "name": current.Name}, nil
	}
	switch kind {
	case "set_photo":
		o, err := cc.GetAddressObject(c, id)
		if err != nil {
			return nil, asError(p.account, err)
		}
		data, _ := op["photoBytes"].([]byte)
		setPhoto(o.Card, data)
		return p.put(sec, id, o.Card)
	case "star", "unstar":
		op = map[string]any{"starred": kind == "star"}
	case "update":
		fields := 0
		for _, k := range []string{
			"name", "givenName", "familyName", "nickname", "emails", "phones", "organization",
			"title", "addresses", "birthday", "notes", "urls", "labels", "starred",
		} {
			if _, has := op[k]; has {
				fields++
			}
		}
		if fields == 0 {
			return nil, core.Errorf("nothing to change: give the fields to set")
		}
	default:
		return nil, core.Errorf("unknown op '%s'", kind)
	}
	// The server's current card: what the app doesn't edit kept.
	o, err := cc.GetAddressObject(c, id)
	if err != nil {
		return nil, asError(p.account, err)
	}
	cats, _, err := categoriesFor(current, op)
	if err != nil {
		return nil, err
	}
	if err := apply(o.Card, op, cats); err != nil {
		return nil, err
	}
	return p.put(sec, id, o.Card)
}
