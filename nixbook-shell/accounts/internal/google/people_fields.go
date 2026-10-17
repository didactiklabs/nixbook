package google

import (
	"maps"
	"regexp"
	"strconv"
	"strings"

	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/contacts"
	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/core"
)

// The fields a change can set; those given replace Google's, the others
// stay as they are.
var contactFields = []string{
	"name", "givenName", "familyName", "nickname", "emails", "phones", "organization",
	"title", "addresses", "birthday", "notes", "urls", "labels", "starred",
}

var listFields = map[string]bool{"emails": true, "phones": true, "urls": true, "addresses": true, "labels": true}

// pickFields keeps a change's contact fields, checking their types: strings
// (null clears), lists, starred a boolean.
func pickFields(op obj) (obj, error) {
	fields := obj{}
	for _, k := range contactFields {
		v, ok := op[k]
		if !ok {
			continue
		}
		switch {
		case listFields[k]:
		case k == "starred":
			if _, ok := v.(bool); !ok {
				return nil, core.Errorf("`starred` must be true or false")
			}
		case v == nil:
			v = ""
		default:
			if _, ok := v.(string); !ok {
				return nil, core.Errorf("`%s` must be a string", k)
			}
		}
		fields[k] = v
	}
	return fields, nil
}

// items is a list field from strings or {value, type, …}; empty entries
// dropped.
func items(v any, field string) ([]obj, error) {
	if v == nil {
		return nil, nil
	}
	raw, ok := v.([]any)
	if !ok {
		raw = []any{v}
	}
	out := []obj{}
	for _, r := range raw {
		var item obj
		switch x := r.(type) {
		case string:
			item = obj{"value": x}
		case obj:
			item = x
		default:
			return nil, core.Errorf("`%s` must be a list of strings or {value, type}", field)
		}
		keys := []string{"value"}
		if field == "addresses" {
			keys = []string{"value", "street", "city", "postalCode", "region", "country"}
		}
		for _, k := range keys {
			if strings.TrimSpace(str(item, k)) != "" {
				out = append(out, item)
				break
			}
		}
	}
	return out, nil
}

// reuse is Google's own copy of an unchanged entry (its metadata, the parts
// the app doesn't show); nil when the entry is new.
func reuse(existing []obj, key, value string) obj {
	for _, e := range existing {
		if contacts.Normalize(str(e, key)) == contacts.Normalize(value) {
			c := maps.Clone(e)
			delete(c, "metadata")
			delete(c, "formattedType")
			return c
		}
	}
	return nil
}

var birthdayRe = regexp.MustCompile(`^(?:(\d{4})|-?-?)-?(\d{1,2})-(\d{1,2})$`)

func membership(group string) obj {
	return obj{"contactGroupMembership": obj{"contactGroupResourceName": "contactGroups/" + group}}
}

// buildFields turns the app's fields into People API ones, for those given:
// the body's parts and the updatePersonFields names. raw is Google's
// current copy (nil for a new contact).
func (p *people) buildFields(sec *contacts.Section, fields obj, raw obj) (obj, []string, error) {
	body, mask := obj{}, []string{}
	if raw == nil {
		raw = obj{}
	}
	has := func(k string) bool { _, ok := fields[k]; return ok }
	sval := func(k string) string { v, _ := fields[k].(string); return v }

	if has("name") || has("givenName") || has("familyName") {
		cur := primary(list(raw, "names"))
		if has("givenName") || has("familyName") {
			n := obj{}
			for _, k := range []string{"middleName", "honorificPrefix", "honorificSuffix"} {
				if v, ok := cur[k]; ok {
					n[k] = v
				}
			}
			given, family := str(cur, "givenName"), str(cur, "familyName")
			if has("givenName") {
				given = sval("givenName")
			}
			if has("familyName") {
				family = sval("familyName")
			}
			n["givenName"], n["familyName"] = given, family
			body["names"] = []obj{}
			if given != "" || family != "" {
				body["names"] = []obj{n}
			}
		} else {
			body["names"] = []obj{}
			if name := sval("name"); name != "" {
				body["names"] = []obj{{"unstructuredName": name}}
			}
		}
		mask = append(mask, "names")
	}
	if has("nickname") {
		body["nicknames"] = []obj{}
		if v := sval("nickname"); v != "" {
			body["nicknames"] = []obj{{"value": v}}
		}
		mask = append(mask, "nicknames")
	}
	for _, f := range [][2]string{{"emails", "emailAddresses"}, {"phones", "phoneNumbers"}, {"urls", "urls"}} {
		if !has(f[0]) {
			continue
		}
		given, err := items(fields[f[0]], f[0])
		if err != nil {
			return nil, nil, err
		}
		out := []obj{}
		for _, v := range given {
			item := reuse(list(raw, f[1]), "value", str(v, "value"))
			if item == nil {
				item = obj{"value": strings.TrimSpace(str(v, "value"))}
			}
			if t := str(v, "type"); t != "" {
				item["type"] = t
			}
			out = append(out, item)
		}
		body[f[1]] = out
		mask = append(mask, f[1])
	}
	if has("organization") || has("title") {
		org := maps.Clone(primary(list(raw, "organizations")))
		delete(org, "metadata")
		delete(org, "formattedType")
		if has("organization") {
			org["name"] = sval("organization")
		}
		if has("title") {
			org["title"] = sval("title")
		}
		body["organizations"] = []obj{}
		if str(org, "name") != "" || str(org, "title") != "" {
			body["organizations"] = []obj{org}
		}
		mask = append(mask, "organizations")
	}
	if has("addresses") {
		given, err := items(fields["addresses"], "addresses")
		if err != nil {
			return nil, nil, err
		}
		out := []obj{}
		for _, v := range given {
			structured := false
			for _, k := range []string{"street", "city", "postalCode", "region", "country"} {
				structured = structured || str(v, k) != ""
			}
			var item obj
			if !structured {
				item = reuse(list(raw, "addresses"), "formattedValue", str(v, "value"))
			}
			if item == nil {
				// Google Contacts shows the structured parts: plain text goes
				// in the street, and Google formats the address from them.
				item = obj{}
				parts := map[string]string{
					"streetAddress": str(v, "street"), "city": str(v, "city"), "region": str(v, "region"),
					"postalCode": str(v, "postalCode"), "country": str(v, "country"),
				}
				if !structured {
					parts["streetAddress"] = strings.TrimSpace(str(v, "value"))
				}
				for k, x := range parts {
					if x != "" {
						item[k] = x
					}
				}
			}
			delete(item, "formattedValue")
			if t := str(v, "type"); t != "" {
				item["type"] = t
			}
			out = append(out, item)
		}
		body["addresses"] = out
		mask = append(mask, "addresses")
	}
	if has("birthday") {
		body["birthdays"] = []obj{}
		if b := strings.TrimSpace(sval("birthday")); b != "" {
			m := birthdayRe.FindStringSubmatch(b)
			var month, day int
			if m != nil {
				month, _ = strconv.Atoi(m[2])
				day, _ = strconv.Atoi(m[3])
			}
			if m == nil || month < 1 || month > 12 || day < 1 || day > 31 {
				return nil, nil, core.Errorf("`birthday` must be YYYY-MM-DD or MM-DD")
			}
			date := obj{"month": month, "day": day}
			if m[1] != "" {
				year, _ := strconv.Atoi(m[1])
				date["year"] = year
			}
			body["birthdays"] = []obj{{"date": date}}
		}
		mask = append(mask, "birthdays")
	}
	if has("notes") {
		body["biographies"] = []obj{}
		if v := sval("notes"); v != "" {
			body["biographies"] = []obj{{"value": v, "contentType": "TEXT_PLAIN"}}
		}
		mask = append(mask, "biographies")
	}
	if has("labels") || has("starred") {
		current := memberships(raw)
		starred := false
		for _, g := range current {
			starred = starred || g == "starred"
		}
		if has("starred") {
			starred = fields["starred"].(bool)
		}
		labels := []string{}
		if has("labels") {
			var given []any
			switch v := fields["labels"].(type) {
			case string:
				given = []any{v}
			case []any:
				given = v
			case nil:
			default:
				return nil, nil, core.Errorf("`labels` must be a list of label names or ids")
			}
			for _, l := range given {
				name, ok := l.(string)
				if !ok || strings.TrimSpace(name) == "" {
					continue
				}
				id, err := p.resolveLabel(sec, name, true)
				if err != nil {
					return nil, nil, err
				}
				labels = append(labels, id)
			}
		} else {
			for _, g := range current {
				if !systemGroups[g] {
					labels = append(labels, g)
				}
			}
		}
		groups := []obj{membership("myContacts")}
		if starred {
			groups = append(groups, membership("starred"))
		}
		seen := map[string]bool{}
		for _, l := range labels {
			if !seen[l] {
				seen[l] = true
				groups = append(groups, membership(l))
			}
		}
		body["memberships"] = groups
		mask = append(mask, "memberships")
	}
	return body, mask, nil
}
