// Package dav is the CalDAV/CardDAV provider: an account on a server that
// speaks the open standards (iCloud, Fastmail, Nextcloud, any other), signed
// in with a user name and an (app) password; its address books are its
// contacts (CardDAV), its calendars that hold to-dos its task lists
// (CalDAV).
package dav

import (
	"bytes"
	"context"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/emersion/go-webdav"
	"github.com/emersion/go-webdav/caldav"
	"github.com/emersion/go-webdav/carddav"

	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/core"
	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/registry"
)

// Preset is a known server: where its contacts and calendars are.
type Preset struct {
	Name        string `json:"name"`
	ContactsURL string `json:"contactsUrl"`
	CalendarURL string `json:"calendarUrl"`
	// Where its app passwords are made.
	PasswordHelp string `json:"passwordHelp"`
	// The server's address is the user's (Nextcloud, custom).
	NeedsURL bool `json:"needsUrl"`
}

// Presets are the servers the accounts window offers.
var Presets = map[string]Preset{
	"icloud": {
		Name: "iCloud", ContactsURL: "https://contacts.icloud.com", CalendarURL: "https://caldav.icloud.com",
		PasswordHelp: "https://account.apple.com/account/manage/section/security",
	},
	"fastmail": {
		Name: "Fastmail", ContactsURL: "https://carddav.fastmail.com", CalendarURL: "https://caldav.fastmail.com",
		PasswordHelp: "https://app.fastmail.com/settings/security/apps",
	},
	"nextcloud": {Name: "Nextcloud", NeedsURL: true},
	"custom":    {Name: "CalDAV/CardDAV", NeedsURL: true},
}

const timeout = 60 * time.Second

type secret struct {
	Password string `json:"password"`
}

func password(a registry.Account) (string, error) {
	var s secret
	ok, err := core.SecretGet(a.SecretKind(), &s)
	if err != nil {
		return "", err
	}
	if !ok || s.Password == "" {
		return "", core.AuthErrorf("%s has no password: sign it in again", a.Name)
	}
	return s.Password, nil
}

// Connected says whether the account has its password.
func Connected(a registry.Account) bool {
	_, err := password(a)
	return err == nil
}

// davHTTP is every DAV request's client: a redirect from https to http
// (the password then sent in clear) refused, an answer read up to
// core.MaxBody only.
var davHTTP = &http.Client{
	Timeout:   timeout,
	Transport: cappedTransport{http.DefaultTransport},
	CheckRedirect: func(req *http.Request, via []*http.Request) error {
		if len(via) >= 10 {
			return errors.New("stopped after 10 redirects")
		}
		if via[0].URL.Scheme == "https" && req.URL.Scheme != "https" {
			return errors.New("refused a redirect from https to http")
		}
		return nil
	},
}

type cappedTransport struct{ http.RoundTripper }

func (t cappedTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	resp, err := t.RoundTripper.RoundTrip(req)
	if err == nil {
		resp.Body = struct {
			io.Reader
			io.Closer
		}{io.LimitReader(resp.Body, core.MaxBody), resp.Body}
	}
	return resp, err
}

// httpClient is a client signed in as the account.
func httpClient(user, pass string) webdav.HTTPClient {
	return webdav.HTTPClientWithBasicAuth(davHTTP, user, pass)
}

// asError says a DAV failure plainly: a refused password is a sign-in to
// redo (exit 2).
func asError(a registry.Account, err error) error {
	if err == nil {
		return nil
	}
	// The library says the status in its error ("HTTP 401 Unauthorized").
	if msg := err.Error(); strings.Contains(msg, "401 Unauthorized") || strings.Contains(msg, "403 Forbidden") {
		return refused(a)
	}
	var urlErr *url.Error
	if errors.As(err, &urlErr) {
		return core.Errorf("can't reach %s: %v", hostOf(urlErr.URL), urlErr.Err)
	}
	return core.Errorf("%s: %v", a.Name, err)
}

func refused(a registry.Account) error {
	return core.AuthErrorf("%s refused the password: sign it in again (an app password, for iCloud and Fastmail)", a.Name)
}

func hostOf(raw string) string {
	if u, err := url.Parse(raw); err == nil && u.Host != "" {
		return u.Host
	}
	return raw
}

func ctx() (context.Context, context.CancelFunc) {
	return context.WithTimeout(context.Background(), 3*timeout)
}

// AddOptions is what adding an account takes.
type AddOptions struct {
	Preset, URL, ContactsURL, CalendarURL, Username, Password, Name string
}

// Add checks the account on its server (the password, where its address
// books and calendars are) and saves it; the same server and user again:
// that account, signed in anew.
func Add(o AddOptions) (registry.Account, error) {
	none := registry.Account{}
	preset, ok := Presets[o.Preset]
	if !ok {
		names := []string{}
		for k := range Presets {
			names = append(names, k)
		}
		return none, core.Errorf("unknown server kind '%s': %s", o.Preset, strings.Join(names, ", "))
	}
	o.URL = strings.TrimRight(strings.TrimSpace(o.URL), "/")
	o.Username = strings.TrimSpace(o.Username)
	if o.Username == "" || o.Password == "" {
		return none, core.Errorf("a user name and a password are needed")
	}
	contactsURL, calendarURL := preset.ContactsURL, preset.CalendarURL
	if preset.NeedsURL {
		if o.URL == "" {
			return none, core.Errorf("%s needs the server's address", preset.Name)
		}
		if !strings.Contains(o.URL, "://") {
			o.URL = "https://" + o.URL
		}
		contactsURL, calendarURL = o.URL, o.URL
		if o.Preset == "nextcloud" && !strings.Contains(o.URL, "/remote.php/") {
			contactsURL, calendarURL = o.URL+"/remote.php/dav", o.URL+"/remote.php/dav"
		}
	}
	if o.ContactsURL != "" {
		contactsURL = strings.TrimRight(o.ContactsURL, "/")
	}
	if o.CalendarURL != "" {
		calendarURL = strings.TrimRight(o.CalendarURL, "/")
	}
	a := registry.Account{
		Provider: "dav", Preset: o.Preset, URL: firstNonEmpty(o.URL, contactsURL), Username: o.Username,
		ContactsURL: contactsURL, CalendarURL: calendarURL, Name: firstNonEmpty(strings.TrimSpace(o.Name), o.Username),
	}
	if strings.Contains(o.Username, "@") {
		a.Email = o.Username
	}
	hc := httpClient(o.Username, o.Password)
	c, cancel := ctx()
	defer cancel()
	// Each service where the server has it; one is enough.
	var contactsErr, calendarErr error
	if a.ContactsHome, contactsErr = contactsHome(c, hc, contactsURL); contactsErr != nil {
		a.ContactsHome = ""
	}
	if a.CalendarHome, calendarErr = calendarHome(c, hc, calendarURL); calendarErr != nil {
		a.CalendarHome = ""
	}
	if a.ContactsHome == "" && a.CalendarHome == "" {
		err := contactsErr
		if err == nil {
			err = calendarErr
		}
		return none, asError(a, err)
	}
	saved, err := registry.Save(a)
	if err != nil {
		return saved, err
	}
	return saved, core.SecretSet(saved.SecretKind(), secret{Password: o.Password})
}

func firstNonEmpty(v ...string) string {
	for _, s := range v {
		if s != "" {
			return s
		}
	}
	return ""
}

// principal is the user's principal on the server, found from its root or
// its well-known address.
func principal(c context.Context, hc webdav.HTTPClient, endpoint, wellKnown string) (*webdav.Client, string, error) {
	var firstErr error
	for _, e := range []string{endpoint, strings.TrimRight(endpoint, "/") + "/.well-known/" + wellKnown} {
		wc, err := webdav.NewClient(hc, e)
		if err != nil {
			return nil, "", err
		}
		p, err := wc.FindCurrentUserPrincipal(c)
		if err == nil && p != "" {
			return wc, p, nil
		}
		if firstErr == nil {
			firstErr = err
		}
	}
	return nil, "", firstErr
}

func contactsHome(c context.Context, hc webdav.HTTPClient, endpoint string) (string, error) {
	_, p, err := principal(c, hc, endpoint, "carddav")
	if err != nil {
		return "", err
	}
	cc, err := carddav.NewClient(hc, endpoint)
	if err != nil {
		return "", err
	}
	return cc.FindAddressBookHomeSet(c, p)
}

func calendarHome(c context.Context, hc webdav.HTTPClient, endpoint string) (string, error) {
	_, p, err := principal(c, hc, endpoint, "caldav")
	if err != nil {
		return "", err
	}
	cc, err := caldav.NewClient(hc, endpoint)
	if err != nil {
		return "", err
	}
	return cc.FindCalendarHomeSet(c, p)
}

// rawRequest sends a WebDAV request the library lacks (MKCALENDAR,
// PROPPATCH), XML body, signed in as the account.
func rawRequest(c context.Context, a registry.Account, method, endpoint, path, body string) error {
	pass, err := password(a)
	if err != nil {
		return err
	}
	base, err := url.Parse(endpoint)
	if err != nil {
		return err
	}
	target, err := base.Parse(path)
	if err != nil {
		return err
	}
	// The password goes to the account's own server only.
	if target.Scheme != base.Scheme || target.Host != base.Host {
		return core.Errorf("%s: refused to send the password to %s", a.Name, hostOf(target.String()))
	}
	req, err := http.NewRequestWithContext(c, method, target.String(), bytes.NewBufferString(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/xml; charset=utf-8")
	req.SetBasicAuth(a.Username, pass)
	resp, err := davHTTP.Do(req)
	if err != nil {
		return asError(a, err)
	}
	defer resp.Body.Close()
	// Capped by davHTTP's transport.
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden {
		return refused(a)
	}
	if resp.StatusCode >= 300 {
		return core.Errorf("%s answered %s to %s", a.Name, resp.Status, method)
	}
	// A multistatus can still say a property was refused.
	if resp.StatusCode == http.StatusMultiStatus && bytes.Contains(data, []byte("HTTP/1.1 4")) {
		return core.Errorf("%s refused the change (%s)", a.Name, method)
	}
	return nil
}

func xmlText(s string) string {
	var b strings.Builder
	_ = xml.EscapeText(&b, []byte(s))
	return b.String()
}

// clients are the account's CardDAV and CalDAV clients.
func cardClient(a registry.Account) (*carddav.Client, error) {
	pass, err := password(a)
	if err != nil {
		return nil, err
	}
	if a.ContactsHome == "" {
		return nil, core.Errorf("%s has no address books", a.Name)
	}
	return carddav.NewClient(httpClient(a.Username, pass), a.ContactsURL)
}

func calClient(a registry.Account) (*caldav.Client, error) {
	pass, err := password(a)
	if err != nil {
		return nil, err
	}
	if a.CalendarHome == "" {
		return nil, core.Errorf("%s has no calendars", a.Name)
	}
	return caldav.NewClient(httpClient(a.Username, pass), a.CalendarURL)
}

func newUID() string {
	return fmt.Sprintf("%x-%x", time.Now().UnixNano(), randomBits())
}
