// Package contacts is the contacts of every account, merged: one local copy
// (contacts.json in the state directory) that the shell's Contacts app and
// widget read, kept in sync by each account's provider (Google People,
// CardDAV…). Changes go to the account's provider first, its answer landing
// in the copy. Ids are global ("<account>:<provider's id>"): the shell and
// agents use them as they are, and this routes each change to its account.
package contacts

import (
	"regexp"
	"slices"
	"strings"
	"unicode"

	"golang.org/x/text/runes"
	"golang.org/x/text/transform"
	"golang.org/x/text/unicode/norm"
)

// Typed is an email, phone or link: its value and its type (home, work,
// mobile… or the user's own).
type Typed struct {
	Value string `json:"value"`
	Type  string `json:"type"`
}

type Address struct {
	Value      string `json:"value"`
	Type       string `json:"type"`
	Street     string `json:"street"`
	City       string `json:"city"`
	Region     string `json:"region"`
	PostalCode string `json:"postalCode"`
	Country    string `json:"country"`
}

// Contact is a contact as the app, the widget and agents see it.
type Contact struct {
	ID           string    `json:"id"`
	Account      string    `json:"account"`
	Name         string    `json:"name"`
	GivenName    string    `json:"givenName"`
	FamilyName   string    `json:"familyName"`
	Nickname     string    `json:"nickname"`
	Emails       []Typed   `json:"emails"`
	Phones       []Typed   `json:"phones"`
	Organization string    `json:"organization"`
	Title        string    `json:"title"`
	Addresses    []Address `json:"addresses"`
	// YYYY-MM-DD, or --MM-DD without the year.
	Birthday string  `json:"birthday"`
	Notes    string  `json:"notes"`
	URLs     []Typed `json:"urls"`
	Photo    string  `json:"photo"`
	Starred  bool    `json:"starred"`
	// Label ids in the copy, names in what list and get answer.
	Labels  []string `json:"labels"`
	Updated string   `json:"updated"`
}

// Label is a contact label (Google's contact groups, vCard categories…).
type Label struct {
	ID      string `json:"id"`
	Account string `json:"account"`
	Name    string `json:"name"`
	Count   int    `json:"count"`
}

// Section is one account's part of the copy, with the provider's own ids:
// what a provider syncs and changes.
type Section struct {
	// The provider's sync state (Google's sync token, a DAV sync token…).
	SyncToken string
	SyncedAt  int64
	Error     string
	Labels    []Label
	Contacts  []Contact
}

// Upsert puts the contact in, replacing the one with its id.
func (s *Section) Upsert(c Contact) {
	s.Contacts = slices.DeleteFunc(s.Contacts, func(x Contact) bool { return x.ID == c.ID })
	s.Contacts = append(s.Contacts, c)
}

// Find is a contact by its id.
func (s *Section) Find(id string) (Contact, bool) {
	for _, c := range s.Contacts {
		if c.ID == id {
			return c, true
		}
	}
	return Contact{}, false
}

// Meta is an account's sync state in the copy.
type Meta struct {
	SyncToken string `json:"syncToken"`
	SyncedAt  int64  `json:"syncedAt"`
	Error     string `json:"error"`
}

// Cache is the local copy: every account's contacts and labels, global ids.
type Cache struct {
	Version  int              `json:"version"`
	Accounts map[string]*Meta `json:"accounts"`
	// The oldest account's last sync, and the first account's failure, for
	// the shell's "synced 5 min ago" and message bar.
	SyncedAt int64     `json:"syncedAt"`
	Error    string    `json:"error"`
	Labels   []Label   `json:"labels"`
	Contacts []Contact `json:"contacts"`
}

var folder = transform.Chain(norm.NFD, runes.Remove(runes.In(unicode.Mn)), norm.NFC)

// Fold is s for comparing and searching: no accents, no case.
func Fold(s string) string {
	out, _, err := transform.String(folder, s)
	if err != nil {
		out = s
	}
	return strings.ToLower(out)
}

var spaces = regexp.MustCompile(`\s+`)

// Normalize is s folded, its spaces made single.
func Normalize(s string) string { return strings.TrimSpace(spaces.ReplaceAllString(Fold(s), " ")) }

func labelNames(cache *Cache, ids []string) []string {
	names := map[string]string{}
	for _, l := range cache.Labels {
		names[l.ID] = l.Name
	}
	out := []string{}
	for _, id := range ids {
		if n, ok := names[id]; ok {
			out = append(out, n)
		}
	}
	return out
}

func sortContacts(cs []Contact) {
	slices.SortStableFunc(cs, func(a, b Contact) int {
		ka, kb := Fold(a.Name), Fold(b.Name)
		// Nameless last.
		if ka == "" {
			ka = "￿"
		}
		if kb == "" {
			kb = "￿"
		}
		if c := strings.Compare(ka, kb); c != 0 {
			return c
		}
		return strings.Compare(a.ID, b.ID)
	})
}
