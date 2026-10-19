// Package registry is the user's accounts (accounts.json in the state
// directory: who and where, never secrets). Each account's secret (an OAuth
// token, a password) is in the keyring under kind "account-<id>"; a
// provider's own OAuth client under "client-<provider>".
package registry

import (
	"fmt"
	"slices"
	"strings"

	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/core"
)

const file = "accounts.json"

// Account is one signed-in account.
type Account struct {
	// Short and stable: "google-1"; the prefix of every id from it
	// ("google-1:c123").
	ID       string `json:"id"`
	Provider string `json:"provider"`
	// What the user sees: the email, or a name they gave.
	Name  string `json:"name"`
	Email string `json:"email,omitempty"`
	// DAV accounts: the server, the user name, which kind of server
	// ("icloud", "fastmail", "nextcloud", "custom"), each service's endpoint
	// and the collections found there (address books' and calendars'
	// homes).
	URL          string `json:"url,omitempty"`
	Username     string `json:"username,omitempty"`
	Preset       string `json:"preset,omitempty"`
	ContactsURL  string `json:"contactsUrl,omitempty"`
	CalendarURL  string `json:"calendarUrl,omitempty"`
	ContactsHome string `json:"contactsHome,omitempty"`
	CalendarHome string `json:"calendarHome,omitempty"`
}

// SecretKind is the keyring kind of the account's secret.
func (a Account) SecretKind() string { return "account-" + a.ID }

type doc struct {
	Accounts []Account `json:"accounts"`
}

func load() doc {
	d := doc{}
	core.ReadJSON(file, &d)
	if d.Accounts == nil {
		d.Accounts = []Account{}
	}
	return d
}

// Local is the built-in account: contacts, task lists and calendars kept on
// this computer only (no sync). Always there, after the others, so new
// things go to a synced account when there is one.
var Local = Account{ID: "local", Provider: "local", Name: "This computer"}

// List is every account, in the order they were added, the local one last.
func List() []Account { return append(load().Accounts, Local) }

// Get is one account by id, or by its name or email (case ignored).
func Get(want string) (Account, error) {
	want = strings.TrimSpace(want)
	accounts := List()
	for _, a := range accounts {
		if a.ID == want || strings.EqualFold(a.Name, want) || (a.Email != "" && strings.EqualFold(a.Email, want)) {
			return a, nil
		}
	}
	names := []string{}
	for _, a := range accounts {
		names = append(names, a.ID+" ("+a.Name+")")
	}
	if len(names) == 0 {
		return Account{}, core.AuthErrorf("no account connected")
	}
	return Account{}, core.Errorf("no account '%s': %s", want, strings.Join(names, ", "))
}

// Save adds the account, or replaces the one with the same provider and
// email (signing in again), keeping its id. New ids: <provider>-<n>.
func Save(a Account) (Account, error) {
	unlock, err := core.Lock("accounts")
	if err != nil {
		return a, err
	}
	defer unlock()
	d := load()
	for i, x := range d.Accounts {
		if x.ID == a.ID || (x.Provider == a.Provider && a.Email != "" && strings.EqualFold(x.Email, a.Email)) ||
			(x.Provider == a.Provider && a.URL != "" && x.URL == a.URL && x.Username == a.Username) {
			a.ID = x.ID
			d.Accounts[i] = a
			return a, core.WriteJSON(file, d)
		}
	}
	if a.Provider == Local.Provider {
		return a, core.Errorf("the local account is built in")
	}
	for n := 1; ; n++ {
		id := fmt.Sprintf("%s-%d", a.Provider, n)
		if !slices.ContainsFunc(d.Accounts, func(x Account) bool { return x.ID == id }) {
			a.ID = id
			break
		}
	}
	d.Accounts = append(d.Accounts, a)
	return a, core.WriteJSON(file, d)
}

// Remove forgets the account and its secret.
func Remove(id string) (Account, error) {
	if id == Local.ID {
		return Account{}, core.Errorf("the local account can't be removed: it is this computer's own")
	}
	unlock, err := core.Lock("accounts")
	if err != nil {
		return Account{}, err
	}
	defer unlock()
	d := load()
	i := slices.IndexFunc(d.Accounts, func(a Account) bool { return a.ID == id })
	if i < 0 {
		return Account{}, core.Errorf("no account '%s'", id)
	}
	a := d.Accounts[i]
	d.Accounts = slices.Delete(d.Accounts, i, i+1)
	if err := core.SecretSet(a.SecretKind(), nil); err != nil {
		return a, err
	}
	return a, core.WriteJSON(file, d)
}

// GlobalID is a provider's id as the shell and agents see it.
func GlobalID(account, id string) string {
	if id == "" {
		return ""
	}
	return account + ":" + id
}

// LocalID is the provider's own id in a global id of that account; "" when
// it is another account's.
func LocalID(account, global string) string {
	if id, ok := strings.CutPrefix(global, account+":"); ok {
		return id
	}
	return ""
}

// SplitID is a global id's account and the provider's own id.
func SplitID(global string) (account, id string, err error) {
	account, id, ok := strings.Cut(strings.TrimSpace(global), ":")
	if !ok || account == "" || id == "" {
		return "", "", core.Errorf("'%s' isn't an id from list (account:id)", global)
	}
	return account, id, nil
}
