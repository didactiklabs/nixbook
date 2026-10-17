package google

import (
	"fmt"
	"slices"
	"strings"

	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/contacts"
)

// Groups that aren't labels: everyone's, starred (its own flag) and the old
// system groups Google Contacts no longer shows.
var systemGroups = map[string]bool{
	"myContacts": true, "starred": true, "all": true, "blocked": true,
	"friends": true, "family": true, "coworkers": true, "chatBuddies": true,
}

const personFields = "names,nicknames,emailAddresses,phoneNumbers,organizations,addresses," +
	"birthdays,biographies,urls,photos,memberships,metadata"

type obj = map[string]any

func str(o obj, key string) string {
	s, _ := o[key].(string)
	return s
}

func list(o obj, key string) []obj {
	items, _ := o[key].([]any)
	out := make([]obj, 0, len(items))
	for _, i := range items {
		if m, ok := i.(obj); ok {
			out = append(out, m)
		}
	}
	return out
}

func num(o obj, key string) int {
	f, _ := o[key].(float64)
	return int(f)
}

func isPrimary(o obj) bool {
	m, _ := o["metadata"].(obj)
	p, _ := m["primary"].(bool)
	return p
}

// primary is Google's primary entry, else the first; empty when none.
func primary(items []obj) obj {
	for _, i := range items {
		if isPrimary(i) {
			return i
		}
	}
	if len(items) > 0 {
		return items[0]
	}
	return obj{}
}

func shortID(resourceName string) string {
	if _, after, ok := strings.Cut(resourceName, "/"); ok {
		return after
	}
	return resourceName
}

func typedList(items []obj) []contacts.Typed {
	out := []contacts.Typed{}
	for _, i := range items {
		if v := str(i, "value"); v != "" {
			out = append(out, contacts.Typed{Value: v, Type: str(i, "type")})
		}
	}
	return out
}

func dateText(d obj) string {
	if d == nil || num(d, "month") == 0 || num(d, "day") == 0 {
		return ""
	}
	if y := num(d, "year"); y != 0 {
		return fmt.Sprintf("%04d-%02d-%02d", y, num(d, "month"), num(d, "day"))
	}
	return fmt.Sprintf("--%02d-%02d", num(d, "month"), num(d, "day"))
}

func addressText(a obj) string {
	if v := str(a, "formattedValue"); v != "" {
		return v
	}
	parts := []string{}
	city := strings.TrimSpace(str(a, "postalCode") + " " + str(a, "city"))
	for _, p := range []string{str(a, "streetAddress"), str(a, "extendedAddress"), city, str(a, "region"), str(a, "country")} {
		if p != "" {
			parts = append(parts, p)
		}
	}
	return strings.Join(parts, "\n")
}

func memberships(person obj) []string {
	out := []string{}
	for _, m := range list(person, "memberships") {
		if g, ok := m["contactGroupMembership"].(obj); ok {
			out = append(out, shortID(str(g, "contactGroupResourceName")))
		}
	}
	return out
}

// simplify is the contact from Google's person (the provider's own ids).
func simplify(person obj) contacts.Contact {
	name := primary(list(person, "names"))
	org := primary(list(person, "organizations"))
	photos := []obj{}
	for _, p := range list(person, "photos") {
		if d, _ := p["default"].(bool); !d {
			photos = append(photos, p)
		}
	}
	groups := memberships(person)
	c := contacts.Contact{
		ID:           shortID(str(person, "resourceName")),
		Name:         str(name, "displayName"),
		GivenName:    str(name, "givenName"),
		FamilyName:   str(name, "familyName"),
		Nickname:     str(primary(list(person, "nicknames")), "value"),
		Emails:       typedList(list(person, "emailAddresses")),
		Phones:       typedList(list(person, "phoneNumbers")),
		Organization: str(org, "name"),
		Title:        str(org, "title"),
		Addresses:    []contacts.Address{},
		Notes:        str(primary(list(person, "biographies")), "value"),
		URLs:         typedList(list(person, "urls")),
		Photo:        str(primary(photos), "url"),
		Starred:      slices.Contains(groups, "starred"),
		Labels:       []string{},
	}
	if c.Name == "" {
		c.Name = str(name, "unstructuredName")
	}
	for _, a := range list(person, "addresses") {
		if text := addressText(a); text != "" {
			c.Addresses = append(c.Addresses, contacts.Address{
				Value: text, Type: str(a, "type"), Street: str(a, "streetAddress"), City: str(a, "city"),
				Region: str(a, "region"), PostalCode: str(a, "postalCode"), Country: str(a, "country"),
			})
		}
	}
	for _, b := range list(person, "birthdays") {
		d, _ := b["date"].(obj)
		if t := dateText(d); t != "" {
			c.Birthday = t
			break
		}
	}
	for _, g := range groups {
		if !systemGroups[g] {
			c.Labels = append(c.Labels, g)
		}
	}
	meta, _ := person["metadata"].(obj)
	for _, s := range list(meta, "sources") {
		if u := str(s, "updateTime"); u > c.Updated {
			c.Updated = u
		}
	}
	return c
}
