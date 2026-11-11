package google

import (
	"fmt"
	"net/mail"
	"net/url"
	"os"
	"slices"
	"strconv"
	"strings"

	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/core"
	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/registry"
)

// What the thread changes do to its labels: {add, remove}.
var threadOps = map[string][2][]string{
	"archive":       {nil, {"INBOX"}},
	"unarchive":     {{"INBOX"}, nil},
	"mark_read":     {nil, {"UNREAD"}},
	"mark_unread":   {{"UNREAD"}, nil},
	"star":          {{"STARRED"}, nil},
	"unstar":        {nil, {"STARRED"}},
	"important":     {{"IMPORTANT"}, nil},
	"not_important": {nil, {"IMPORTANT"}},
	"spam":          {{"SPAM"}, {"INBOX"}},
	"not_spam":      {{"INBOX"}, {"SPAM"}},
	"label":         {nil, nil},
	"trash":         {nil, nil},
	"untrash":       {nil, nil},
}

// MailOps is every change `mail apply` takes.
var MailOps = []string{
	"archive", "unarchive", "mark_read", "mark_unread", "star", "unstar", "important",
	"not_important", "spam", "not_spam", "label", "trash", "untrash", "draft", "send", "send_draft", "delete_draft",
	"create_label", "rename_label", "delete_label", "create_filter", "delete_filter", "replace_filter",
	"save_attachment",
}

func opStr(op map[string]any, key string) string {
	s, _ := op[key].(string)
	return strings.TrimSpace(s)
}

func opBool(op map[string]any, key string) bool {
	b, _ := op[key].(bool)
	return b
}

// opList is a field given as a list or a single string ("a, b" split
// when split).
func opList(op map[string]any, key string, split bool) []string {
	out := []string{}
	add := func(s string) {
		if split {
			for _, p := range strings.Split(s, ",") {
				if p = strings.TrimSpace(p); p != "" {
					out = append(out, p)
				}
			}
		} else if s = strings.TrimSpace(s); s != "" {
			out = append(out, s)
		}
	}
	switch v := op[key].(type) {
	case string:
		add(v)
	case []any:
		for _, x := range v {
			if s, ok := x.(string); ok {
				add(s)
			}
		}
	}
	return out
}

// ApplyMail runs each change on its own (`mail apply`).
func ApplyMail(request any) ([]core.Result, error) {
	ops, err := core.Ops(request, 50)
	if err != nil {
		return nil, err
	}
	return core.RunOps(ops, applyMail)
}

func applyMail(op map[string]any) (any, error) {
	kind := core.Kind(op)
	if _, ok := threadOps[kind]; ok {
		return threadChange(kind, op)
	}
	switch kind {
	case "draft", "send":
		return compose(kind, op)
	case "send_draft", "delete_draft":
		box, id, err := mailboxOf(opStr(op, "id"))
		if err != nil {
			return nil, err
		}
		if kind == "delete_draft" {
			return map[string]any{"deleted": opStr(op, "id")}, box.call("DELETE", "/drafts/"+url.PathEscape(id), nil, nil)
		}
		var r gMessage
		if err := box.call("POST", "/drafts/send", map[string]any{"id": id}, &r); err != nil {
			return nil, err
		}
		return map[string]any{"sent": registry.GlobalID(box.Account.ID, r.ID), "thread": registry.GlobalID(box.Account.ID, r.ThreadID)}, nil
	case "create_label", "rename_label", "delete_label":
		return labelChange(kind, op)
	case "create_filter", "delete_filter", "replace_filter":
		return filterChange(kind, op)
	case "save_attachment":
		return SaveAttachment(opStr(op, "message"), opStr(op, "part"), opStr(op, "dir"))
	}
	return nil, core.Errorf("unknown change '%s': %s", kind, strings.Join(MailOps, ", "))
}

// threadChange: the threads given (`ids`, or `id`), each through its own
// account.
func threadChange(kind string, op map[string]any) (any, error) {
	ids := opList(op, "ids", false)
	ids = append(ids, opList(op, "id", false)...)
	if len(ids) == 0 || len(ids) > 100 {
		return nil, core.Errorf("%s needs ids: 1 to 100 threads' ids (from search)", kind)
	}
	add := append([]string{}, threadOps[kind][0]...)
	remove := append([]string{}, threadOps[kind][1]...)
	boxes := map[string]*Mailbox{}
	done := []string{}
	for _, global := range ids {
		acct, tid, err := registry.SplitID(global)
		if err != nil {
			return nil, err
		}
		box := boxes[acct]
		if box == nil {
			if box, err = OneMailbox(acct); err != nil {
				return nil, err
			}
			boxes[acct] = box
			if kind == "label" {
				// The labels are each account's own.
				add, remove = []string{}, []string{}
				for _, name := range opList(op, "add", false) {
					id, err := box.labelID(name, true)
					if err != nil {
						return nil, err
					}
					add = append(add, id)
				}
				for _, name := range opList(op, "remove", false) {
					id, err := box.labelID(name, false)
					if err != nil {
						return nil, err
					}
					remove = append(remove, id)
				}
				if len(add)+len(remove) == 0 {
					return nil, core.Errorf("label needs add or remove: label names")
				}
			}
		}
		path := "/threads/" + url.PathEscape(tid)
		switch kind {
		case "trash", "untrash":
			err = box.call("POST", path+"/"+kind, nil, nil)
		default:
			err = box.call("POST", path+"/modify", map[string]any{"addLabelIds": add, "removeLabelIds": remove}, nil)
		}
		if err != nil {
			if len(done) > 0 {
				return nil, core.Errorf("%s: %d done (%s), then %s: %v", kind, len(done), strings.Join(done, ", "), global, err)
			}
			return nil, err
		}
		done = append(done, global)
	}
	return map[string]any{"done": len(done), "ids": done}, nil
}

// addresses parses a field's recipients ("A <a@x>, b@y", or a list).
func addresses(op map[string]any, key string) ([]*mail.Address, error) {
	list := opList(op, key, false)
	if len(list) == 0 {
		return nil, nil
	}
	out, err := mail.ParseAddressList(strings.Join(list, ", "))
	if err != nil {
		return nil, core.Errorf("`%s` isn't a list of addresses: %v", key, err)
	}
	return out, nil
}

func sameAddress(a, b *mail.Address) bool { return strings.EqualFold(a.Address, b.Address) }

// compose makes the message of a draft or a send: a new one, or a reply
// (`replyTo`: a thread's id; its last message answered, `replyAll`: everyone
// on it).
func compose(kind string, op map[string]any) (any, error) {
	var box *Mailbox
	var err error
	var threadID string
	o := outgoing{Subject: opStr(op, "subject"), Body: opStr(op, "body")}
	if v, ok := op["body"].(string); ok {
		o.Body = v
	}
	if o.To, err = addresses(op, "to"); err != nil {
		return nil, err
	}
	if o.Cc, err = addresses(op, "cc"); err != nil {
		return nil, err
	}
	if o.Bcc, err = addresses(op, "bcc"); err != nil {
		return nil, err
	}
	if reply := opStr(op, "replyTo"); reply != "" {
		if box, threadID, err = mailboxOf(reply); err != nil {
			return nil, err
		}
		t, err := box.thread(threadID, "metadata", "From", "To", "Cc", "Reply-To", "Subject", "Message-ID", "References")
		if err != nil {
			return nil, err
		}
		last := t.Messages[len(t.Messages)-1]
		for i := len(t.Messages) - 1; i >= 0; i-- {
			if !t.Messages[i].has("SENT") && !t.Messages[i].has("DRAFT") {
				last = t.Messages[i]
				break
			}
		}
		p := last.Payload
		msgID := p.header("Message-ID")
		o.InReplyTo = msgID
		o.References = strings.TrimSpace(p.header("References") + " " + msgID)
		if o.Subject == "" {
			o.Subject = p.header("Subject")
			if !strings.HasPrefix(strings.ToLower(o.Subject), "re:") {
				o.Subject = "Re: " + o.Subject
			}
		}
		if len(o.To) == 0 {
			src := p.header("Reply-To")
			if src == "" {
				src = p.header("From")
			}
			if last.has("SENT") {
				src = p.header("To")
			}
			o.To, _ = mail.ParseAddressList(src)
		}
		if opBool(op, "replyAll") {
			me := &mail.Address{Address: box.Account.Email}
			others, _ := mail.ParseAddressList(strings.Trim(p.header("To")+", "+p.header("Cc"), ", "))
			for _, a := range others {
				if sameAddress(a, me) || slices.ContainsFunc(o.To, func(x *mail.Address) bool { return sameAddress(x, a) }) ||
					slices.ContainsFunc(o.Cc, func(x *mail.Address) bool { return sameAddress(x, a) }) {
					continue
				}
				o.Cc = append(o.Cc, a)
			}
		}
	} else if box, err = OneMailbox(opStr(op, "account")); err != nil {
		return nil, err
	}
	if len(o.To)+len(o.Cc)+len(o.Bcc) == 0 && kind == "send" {
		return nil, core.Errorf("send needs a recipient (to)")
	}
	if len(o.To)+len(o.Cc)+len(o.Bcc) > 100 {
		return nil, core.Errorf("at most 100 recipients")
	}
	if strings.TrimSpace(o.Body) == "" && kind == "send" {
		return nil, core.Errorf("send needs a body")
	}
	o.From = &mail.Address{Address: box.Account.Email}
	size := 0
	for _, path := range opList(op, "attachments", false) {
		info, err := os.Stat(path)
		if err != nil || !info.Mode().IsRegular() {
			return nil, core.Errorf("can't attach %s: not a file", path)
		}
		if size += int(info.Size()); size > MaxAttachments {
			return nil, core.Errorf("the attachments are over %d MB (Gmail's limit): share a link instead", MaxAttachments>>20)
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return nil, core.Errorf("can't read %s: %v", path, err)
		}
		o.Files = append(o.Files, outFile{Name: safeFileName(path), Data: data})
	}
	raw := o.raw()
	var r struct {
		ID       string   `json:"id"`
		ThreadID string   `json:"threadId"`
		Message  gMessage `json:"message"`
	}
	if kind == "draft" {
		msg := map[string]any{}
		if threadID != "" {
			msg["threadId"] = threadID
		}
		if len(raw) > inlineLimit() {
			err = box.upload("/drafts", map[string]any{"message": msg}, raw, &r)
		} else {
			msg["raw"] = encodeRaw(raw)
			err = box.call("POST", "/drafts", map[string]any{"message": msg}, &r)
		}
	} else {
		meta := map[string]any{}
		if threadID != "" {
			meta["threadId"] = threadID
		}
		if len(raw) > inlineLimit() {
			err = box.upload("/messages/send", meta, raw, &r)
		} else {
			meta["raw"] = encodeRaw(raw)
			err = box.call("POST", "/messages/send", meta, &r)
		}
	}
	if err != nil {
		return nil, err
	}
	out := map[string]any{
		"account": box.Account.Email, "to": joinAddresses(o.To), "subject": o.Subject,
	}
	if len(o.Cc) > 0 {
		out["cc"] = joinAddresses(o.Cc)
	}
	if len(o.Files) > 0 {
		names := []string{}
		for _, f := range o.Files {
			names = append(names, f.Name)
		}
		out["attachments"] = names
	}
	if kind == "draft" {
		out["draft"] = registry.GlobalID(box.Account.ID, r.ID)
		out["thread"] = registry.GlobalID(box.Account.ID, r.Message.ThreadID)
	} else {
		out["sent"] = registry.GlobalID(box.Account.ID, r.ID)
		out["thread"] = registry.GlobalID(box.Account.ID, r.ThreadID)
	}
	return out, nil
}

func labelChange(kind string, op map[string]any) (any, error) {
	box, err := OneMailbox(opStr(op, "account"))
	if err != nil {
		return nil, err
	}
	if kind == "create_label" {
		name := opStr(op, "name")
		if name == "" {
			return nil, core.Errorf("create_label needs a name (\"Parent/Child\" nests it)")
		}
		if id, err := box.labelID(name, false); err == nil {
			return map[string]any{"label": name, "existed": true, "id": id}, nil
		}
		l, err := box.createLabel(name)
		return map[string]any{"label": l.Name, "created": true}, err
	}
	id, err := box.labelID(opStr(op, "label"), false)
	if err != nil {
		return nil, err
	}
	if _, system := systemLabels[id]; system {
		return nil, core.Errorf("%s is one of Gmail's own labels: it can't be changed", opStr(op, "label"))
	}
	if kind == "delete_label" {
		// Its mail stays (only the label goes).
		return map[string]any{"deleted": opStr(op, "label")}, box.call("DELETE", "/labels/"+url.PathEscape(id), nil, nil)
	}
	name := opStr(op, "name")
	if name == "" {
		return nil, core.Errorf("rename_label needs the new name")
	}
	var l gLabel
	err = box.call("PATCH", "/labels/"+url.PathEscape(id), map[string]any{"name": name}, &l)
	return map[string]any{"label": l.Name, "was": opStr(op, "label")}, err
}

// parseSize is "5M", "200k" or bytes.
func parseSize(v any) (int, error) {
	switch s := v.(type) {
	case float64:
		return int(s), nil
	case string:
		s = strings.ToLower(strings.TrimSpace(s))
		mult := 1
		switch {
		case strings.HasSuffix(s, "m") || strings.HasSuffix(s, "mb"):
			mult, s = 1<<20, strings.TrimRight(s, "mb")
		case strings.HasSuffix(s, "k") || strings.HasSuffix(s, "kb"):
			mult, s = 1<<10, strings.TrimRight(s, "kb")
		}
		n, err := strconv.ParseFloat(strings.TrimSpace(s), 64)
		if err == nil && n > 0 {
			return int(n * float64(mult)), nil
		}
	}
	return 0, core.Errorf("a size is bytes, or like \"5M\" or \"200k\"")
}

func sizeText(n int) string {
	if n >= 1<<20 && n%(1<<20) == 0 {
		return fmt.Sprintf("%dM", n>>20)
	}
	if n >= 1<<10 && n%(1<<10) == 0 {
		return fmt.Sprintf("%dk", n>>10)
	}
	return strconv.Itoa(n)
}
