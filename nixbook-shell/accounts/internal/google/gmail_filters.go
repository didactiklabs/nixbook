package google

import (
	"net/url"
	"strconv"
	"strings"

	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/core"
	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/registry"
)

// Gmail's filters (server side: they sort new mail as it arrives, whatever
// app reads it). Editing one is replacing it: Gmail has no update.

type gFilter struct {
	ID       string         `json:"id,omitempty"`
	Criteria map[string]any `json:"criteria"`
	Action   struct {
		AddLabelIDs    []string `json:"addLabelIds,omitempty"`
		RemoveLabelIDs []string `json:"removeLabelIds,omitempty"`
		Forward        string   `json:"forward,omitempty"`
	} `json:"action"`
}

var criteriaText = []string{"from", "to", "subject", "query", "notQuery"}

// filterCriteria is the tool's criteria as Gmail's.
func filterCriteria(in map[string]any) (map[string]any, error) {
	out := map[string]any{}
	for _, k := range criteriaText {
		v, _ := in[k].(string)
		if k == "notQuery" && v == "" {
			v, _ = in["negatedQuery"].(string)
		}
		if v = strings.TrimSpace(v); v == "" {
			continue
		}
		if len(v) > 1500 {
			return nil, core.Errorf("`%s` is too long", k)
		}
		if k == "notQuery" {
			k = "negatedQuery"
		}
		out[k] = v
	}
	for _, k := range []string{"hasAttachment", "excludeChats"} {
		if b, ok := in[k].(bool); ok && b {
			out[k] = true
		}
	}
	for _, k := range []string{"larger", "smaller"} {
		if v, ok := in[k]; ok && v != nil {
			n, err := parseSize(v)
			if err != nil {
				return nil, err
			}
			if _, has := out["size"]; has {
				return nil, core.Errorf("a filter takes larger or smaller, not both")
			}
			out["size"], out["sizeComparison"] = n, k
		}
	}
	if len(out) == 0 || len(out) == 1 && out["excludeChats"] != nil {
		return nil, core.Errorf("a filter needs criteria: from, to, subject, query, notQuery, hasAttachment, larger or smaller")
	}
	return out, nil
}

// friendlyCriteria is Gmail's criteria as the tool's.
func friendlyCriteria(c map[string]any) map[string]any {
	out := map[string]any{}
	for k, v := range c {
		switch k {
		case "negatedQuery":
			out["notQuery"] = v
		case "size", "sizeComparison":
		default:
			out[k] = v
		}
	}
	if n, ok := c["size"].(float64); ok {
		if cmp, _ := c["sizeComparison"].(string); cmp == "smaller" {
			out["smaller"] = sizeText(int(n))
		} else {
			out["larger"] = sizeText(int(n))
		}
	} else if n, ok := c["size"].(int); ok {
		out[c["sizeComparison"].(string)] = sizeText(n)
	}
	return out
}

// criteriaQuery is the Gmail search a filter's criteria make (to apply it
// to the mail already there, as Gmail's "also apply" does).
func criteriaQuery(c map[string]any) string {
	parts := []string{}
	for _, k := range []string{"from", "to", "subject"} {
		if v, _ := c[k].(string); v != "" {
			parts = append(parts, k+":("+v+")")
		}
	}
	if v, _ := c["query"].(string); v != "" {
		parts = append(parts, "("+v+")")
	}
	if v, _ := c["negatedQuery"].(string); v != "" {
		parts = append(parts, "-("+v+")")
	}
	if b, _ := c["hasAttachment"].(bool); b {
		parts = append(parts, "has:attachment")
	}
	var size int
	switch n := c["size"].(type) {
	case int:
		size = n
	case float64:
		size = int(n)
	}
	if size > 0 {
		cmp, _ := c["sizeComparison"].(string)
		parts = append(parts, cmp+":"+strconv.Itoa(size))
	}
	return strings.Join(parts, " ")
}

var categories = map[string]string{
	"primary": "CATEGORY_PERSONAL", "social": "CATEGORY_SOCIAL", "promotions": "CATEGORY_PROMOTIONS",
	"updates": "CATEGORY_UPDATES", "forums": "CATEGORY_FORUMS",
}

// filterAction is the tool's action as Gmail's label changes; labels named
// are made when missing.
func (m *Mailbox) filterAction(in map[string]any) (add, remove []string, err error) {
	if f, _ := in["forward"].(string); strings.TrimSpace(f) != "" {
		return nil, nil, core.Errorf("filters that forward mail aren't offered here (that would send the user's mail " +
			"elsewhere): set it up in Gmail itself")
	}
	add, remove = []string{}, []string{}
	for _, name := range append(opList(in, "label", false), opList(in, "labels", false)...) {
		id, err := m.labelID(name, true)
		if err != nil {
			return nil, nil, err
		}
		add = append(add, id)
	}
	for _, name := range opList(in, "removeLabels", false) {
		id, err := m.labelID(name, false)
		if err != nil {
			return nil, nil, err
		}
		remove = append(remove, id)
	}
	flags := []struct {
		key, label string
		adds       bool
	}{
		{"archive", "INBOX", false},
		{"markRead", "UNREAD", false},
		{"star", "STARRED", true},
		{"important", "IMPORTANT", true},
		{"notImportant", "IMPORTANT", false},
		{"trash", "TRASH", true},
		{"neverSpam", "SPAM", false},
	}
	for _, f := range flags {
		if opBool(in, f.key) {
			if f.adds {
				add = append(add, f.label)
			} else {
				remove = append(remove, f.label)
			}
		}
	}
	if c := strings.ToLower(opStr(in, "category")); c != "" {
		id, ok := categories[c]
		if !ok {
			return nil, nil, core.Errorf("category: primary, social, promotions, updates or forums")
		}
		add = append(add, id)
	}
	if len(add)+len(remove) == 0 {
		return nil, nil, core.Errorf("a filter needs an action: label, archive, markRead, star, important, " +
			"notImportant, trash, neverSpam or category")
	}
	return add, remove, nil
}

// describe is a filter in words: "from:(x) → label Receipts, skip the
// inbox, mark read".
func (m *Mailbox) describe(f gFilter) (string, []string) {
	does := []string{}
	for _, id := range f.Action.AddLabelIDs {
		switch id {
		case "STARRED":
			does = append(does, "star")
		case "IMPORTANT":
			does = append(does, "mark important")
		case "TRASH":
			does = append(does, "delete (to the trash)")
		default:
			if strings.HasPrefix(id, "CATEGORY_") {
				does = append(does, "categorise as "+systemLabels[id])
			} else {
				does = append(does, "label "+strings.Join(m.names([]string{id}), ""))
			}
		}
	}
	for _, id := range f.Action.RemoveLabelIDs {
		switch id {
		case "INBOX":
			does = append(does, "skip the inbox")
		case "UNREAD":
			does = append(does, "mark read")
		case "IMPORTANT":
			does = append(does, "never mark important")
		case "SPAM":
			does = append(does, "never send to spam")
		default:
			does = append(does, "remove label "+strings.Join(m.names([]string{id}), ""))
		}
	}
	if f.Action.Forward != "" {
		does = append(does, "forward to "+f.Action.Forward)
	}
	return criteriaQuery(f.Criteria) + " → " + strings.Join(does, ", "), does
}

func (m *Mailbox) filterOut(f gFilter) map[string]any {
	text, does := m.describe(f)
	return map[string]any{
		"id": registry.GlobalID(m.Account.ID, f.ID), "account": m.Account.Email,
		"criteria": friendlyCriteria(f.Criteria), "does": does, "description": text,
	}
}

// Filters is the account's filters.
func Filters(account string) (map[string]any, error) {
	boxes, err := Mailboxes(account)
	if err != nil {
		return nil, err
	}
	all := []map[string]any{}
	for _, box := range boxes {
		var r struct {
			Filter []gFilter `json:"filter"`
		}
		if err := box.call("GET", "/settings/filters", nil, &r); err != nil {
			return nil, err
		}
		if _, err := box.Labels(); err != nil {
			return nil, err
		}
		for _, f := range r.Filter {
			all = append(all, box.filterOut(f))
		}
	}
	return map[string]any{"filters": all}, nil
}

func (m *Mailbox) getFilter(id string) (gFilter, error) {
	var f gFilter
	err := m.call("GET", "/settings/filters/"+url.PathEscape(id), nil, &f)
	return f, err
}

// applyExisting gives the mail already matching what the filter does to
// new mail (at most applyMax messages).
func (m *Mailbox) applyExisting(f gFilter) (int, error) {
	q := criteriaQuery(f.Criteria)
	ids, page := []string{}, ""
	for len(ids) < applyMax {
		v := url.Values{"q": {q}, "maxResults": {"500"}}
		if page != "" {
			v.Set("pageToken", page)
		}
		var r struct {
			Messages []struct {
				ID string `json:"id"`
			} `json:"messages"`
			Next string `json:"nextPageToken"`
		}
		if err := m.call("GET", "/messages?"+v.Encode(), nil, &r); err != nil {
			return 0, err
		}
		for _, msg := range r.Messages {
			ids = append(ids, msg.ID)
		}
		if page = r.Next; page == "" {
			break
		}
	}
	ids = ids[:min(len(ids), applyMax)]
	for i := 0; i < len(ids); i += 1000 {
		chunk := ids[i:min(i+1000, len(ids))]
		if err := m.call("POST", "/messages/batchModify", map[string]any{
			"ids": chunk, "addLabelIds": append([]string{}, f.Action.AddLabelIDs...),
			"removeLabelIds": append([]string{}, f.Action.RemoveLabelIDs...),
		}, nil); err != nil {
			return i, err
		}
	}
	return len(ids), nil
}

func filterChange(kind string, op map[string]any) (any, error) {
	var box *Mailbox
	var old gFilter
	var err error
	if kind != "create_filter" {
		var id string
		if box, id, err = mailboxOf(opStr(op, "id")); err != nil {
			return nil, err
		}
		if old, err = box.getFilter(id); err != nil {
			return nil, err
		}
		if _, err := box.Labels(); err != nil {
			return nil, err
		}
		if kind == "delete_filter" {
			if err := box.call("DELETE", "/settings/filters/"+url.PathEscape(id), nil, nil); err != nil {
				return nil, err
			}
			text, _ := box.describe(old)
			return map[string]any{"deleted": opStr(op, "id"), "was": text}, nil
		}
	} else if box, err = OneMailbox(opStr(op, "account")); err != nil {
		return nil, err
	}
	f := gFilter{Criteria: old.Criteria}
	f.Action = old.Action
	if c, ok := op["criteria"].(map[string]any); ok {
		if f.Criteria, err = filterCriteria(c); err != nil {
			return nil, err
		}
	} else if kind == "create_filter" {
		return nil, core.Errorf("create_filter needs criteria {from?, to?, subject?, query?, notQuery?, hasAttachment?, larger?, smaller?}")
	}
	if a, ok := op["action"].(map[string]any); ok {
		if f.Action.AddLabelIDs, f.Action.RemoveLabelIDs, err = box.filterAction(a); err != nil {
			return nil, err
		}
		f.Action.Forward = ""
	} else if kind == "create_filter" {
		return nil, core.Errorf("create_filter needs an action {label?, archive?, markRead?, star?, important?, notImportant?, trash?, neverSpam?, category?}")
	} else if old.Action.Forward != "" {
		return nil, core.Errorf("that filter forwards mail: change it in Gmail itself")
	}
	var made gFilter
	if err := box.call("POST", "/settings/filters", f, &made); err != nil {
		return nil, err
	}
	out := box.filterOut(made)
	if kind == "replace_filter" {
		// The new one is in place before the old one goes.
		if err := box.call("DELETE", "/settings/filters/"+url.PathEscape(old.ID), nil, nil); err != nil {
			out["error"] = "the new filter is made, but the old one couldn't be deleted: " + err.Error()
		}
		was, _ := box.describe(old)
		out["replaced"] = was
	}
	if opBool(op, "applyExisting") {
		n, err := box.applyExisting(made)
		out["appliedTo"] = n
		if err != nil {
			out["applyError"] = err.Error()
		} else if n == applyMax {
			out["applyNote"] = "applied to the newest " + strconv.Itoa(applyMax) + " messages only"
		}
	}
	return out, nil
}
