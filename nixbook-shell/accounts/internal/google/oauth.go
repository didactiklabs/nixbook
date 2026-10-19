// Package google is the Google provider: the sign-in (the user's own OAuth
// client, one consent for contacts, tasks and calendar, a token per
// account), Google Contacts (People API) and Google Tasks.
package google

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/core"
	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/registry"
)

// Scopes: the one consent covers every service (contacts, tasks,
// calendar).
var Scopes = []string{
	"https://www.googleapis.com/auth/contacts",
	"https://www.googleapis.com/auth/tasks",
	"https://www.googleapis.com/auth/calendar",
	"openid",
	"email",
}

const (
	ConsoleURL   = "https://console.cloud.google.com/apis/credentials"
	LoginTimeout = 5 * time.Minute
	clientKind   = "client-google"
)

// APILibrary is the APIs to enable in the client's Google Cloud project.
var APILibrary = map[string]string{
	"people":   "https://console.cloud.google.com/apis/library/people.googleapis.com",
	"tasks":    "https://console.cloud.google.com/apis/library/tasks.googleapis.com",
	"calendar": "https://console.cloud.google.com/apis/library/calendar-json.googleapis.com",
}

func authURL() string {
	return core.Endpoint("NIXBOOK_ACCOUNTS_GOOGLE_AUTH_URL", "https://accounts.google.com/o/oauth2/v2/auth")
}

func tokenURL() string {
	return core.Endpoint("NIXBOOK_ACCOUNTS_GOOGLE_TOKEN_URL", "https://oauth2.googleapis.com/token")
}

func revokeURL() string {
	return core.Endpoint("NIXBOOK_ACCOUNTS_GOOGLE_REVOKE_URL", "https://oauth2.googleapis.com/revoke")
}

// Client is the user's own OAuth client (Google Cloud, "Desktop app").
// DankCalendar's built-in client is for DankCalendar only.
type Client struct {
	ID     string `json:"client_id"`
	Secret string `json:"client_secret"`
}

// Token is a signed-in account's.
type Token struct {
	Refresh string  `json:"refresh_token"`
	Access  string  `json:"access_token,omitempty"`
	Expiry  float64 `json:"expiry,omitempty"`
	Email   string  `json:"email,omitempty"`
}

// ParseClient reads a downloaded client JSON ({"installed": {…}}, "web",
// or the bare values).
func ParseClient(data []byte) (Client, error) {
	var doc struct {
		Installed *Client `json:"installed"`
		Web       *Client `json:"web"`
		Client
	}
	if err := json.Unmarshal(data, &doc); err != nil {
		return Client{}, core.Errorf("not a Google OAuth client: %v", err)
	}
	c := doc.Client
	if doc.Installed != nil {
		c = *doc.Installed
	} else if doc.Web != nil {
		c = *doc.Web
	}
	return checkClient(c)
}

func checkClient(c Client) (Client, error) {
	c.ID, c.Secret = strings.TrimSpace(c.ID), strings.TrimSpace(c.Secret)
	if c.ID == "" || c.Secret == "" {
		return Client{}, core.Errorf("not a Google OAuth client: expected client_id and client_secret")
	}
	return c, nil
}

// SetupClient saves the client: from a file, the newest
// ~/Downloads/client_secret*.json ("--find"), or both values.
func SetupClient(file, id, secret string) (Client, error) {
	var c Client
	var err error
	if id != "" || secret != "" {
		c, err = checkClient(Client{ID: id, Secret: secret})
	} else {
		if file == "--find" {
			if file, err = findClientFile(); err != nil {
				return Client{}, err
			}
		}
		data, rerr := os.ReadFile(expandHome(file))
		if rerr != nil {
			return Client{}, core.Errorf("can't read %s: %v", file, rerr)
		}
		c, err = ParseClient(data)
	}
	if err != nil {
		return Client{}, err
	}
	return c, core.SecretSet(clientKind, c)
}

func expandHome(p string) string {
	if strings.HasPrefix(p, "~/") {
		if home, err := os.UserHomeDir(); err == nil {
			return filepath.Join(home, p[2:])
		}
	}
	return p
}

func findClientFile() (string, error) {
	dir := core.Getenv("XDG_DOWNLOAD_DIR")
	if dir == "" {
		dir = expandHome("~/Downloads")
	}
	files, _ := filepath.Glob(filepath.Join(dir, "client_secret*.json"))
	if len(files) == 0 {
		return "", core.Errorf("no client_secret*.json in %s: download the OAuth client's JSON first", dir)
	}
	sort.Slice(files, func(i, j int) bool {
		a, _ := os.Stat(files[i])
		b, _ := os.Stat(files[j])
		return a != nil && b != nil && a.ModTime().After(b.ModTime())
	})
	return files[0], nil
}

// Configured says whether the client is set up.
func Configured() (bool, error) {
	var c Client
	return core.SecretGet(clientKind, &c)
}

// LoadClient is the saved client.
func LoadClient() (Client, error) {
	var c Client
	ok, err := core.SecretGet(clientKind, &c)
	if err != nil {
		return c, err
	}
	if !ok {
		return c, core.AuthErrorf("no Google OAuth client yet: set one up first (nixbook-accounts setup google)")
	}
	return c, nil
}

// LoadToken is the account's token, if it has one.
func LoadToken(a registry.Account) (*Token, error) {
	var t Token
	ok, err := core.SecretGet(a.SecretKind(), &t)
	if err != nil || !ok || t.Refresh == "" {
		return nil, err
	}
	return &t, nil
}

// AccessToken is a valid access token for the account, refreshed when it
// is about to expire.
func AccessToken(a registry.Account) (string, error) {
	t, err := LoadToken(a)
	if err != nil {
		return "", err
	}
	if t == nil {
		return "", core.AuthErrorf("%s is signed out: connect it again", a.Name)
	}
	now := float64(time.Now().Unix())
	if t.Access != "" && t.Expiry > now+60 {
		return t.Access, nil
	}
	c, err := LoadClient()
	if err != nil {
		return "", err
	}
	var r struct {
		Access    string `json:"access_token"`
		ExpiresIn int    `json:"expires_in"`
	}
	err = core.Call("POST", tokenURL(), nil, url.Values{
		"grant_type": {"refresh_token"}, "refresh_token": {t.Refresh},
		"client_id": {c.ID}, "client_secret": {c.Secret},
	}, "", &r)
	var api *core.APIError
	if errors.As(err, &api) && (strings.Contains(api.Reason, "invalid_grant") || strings.Contains(api.Reason, "invalid_client")) {
		_ = core.SecretSet(a.SecretKind(), nil)
		return "", core.AuthErrorf("Google signed %s out (access revoked or expired): connect it again", a.Name)
	}
	if err != nil {
		return "", err
	}
	t.Access = r.Access
	t.Expiry = now + float64(expiresIn(r.ExpiresIn))
	return t.Access, core.SecretSet(a.SecretKind(), t)
}

func expiresIn(s int) int {
	if s <= 0 {
		return 3600
	}
	return s
}

func randomURLSafe(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return base64.RawURLEncoding.EncodeToString(b)
}

func idTokenEmail(idToken string) string {
	parts := strings.Split(idToken, ".")
	if len(parts) < 2 {
		return ""
	}
	data, err := base64.RawURLEncoding.DecodeString(strings.TrimRight(parts[1], "="))
	if err != nil {
		return ""
	}
	var claims struct {
		Email string `json:"email"`
	}
	_ = json.Unmarshal(data, &claims)
	return claims.Email
}

// Login opens Google's consent page (PKCE, the answer on 127.0.0.1), saves
// the account (the same email again: the same account, signed in anew) and
// its token. Its first line on out is {"authUrl": …}, for the app's "copy
// the link" when no browser opens.
func Login(openBrowser bool, out io.Writer) (registry.Account, error) {
	none := registry.Account{}
	c, err := LoadClient()
	if err != nil {
		return none, err
	}
	verifier := randomURLSafe(48)
	sum := sha256.Sum256([]byte(verifier))
	challenge := base64.RawURLEncoding.EncodeToString(sum[:])
	state := randomURLSafe(18)

	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return none, err
	}
	redirect := fmt.Sprintf("http://127.0.0.1:%d", ln.Addr().(*net.TCPAddr).Port)
	got := make(chan url.Values, 1)
	srv := &http.Server{Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query()
		if q.Get("state") != state {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		msg := "Google account connected. You can close this tab."
		if q.Get("code") == "" {
			msg = "Google said: " + q.Get("error") + ". You can close this tab."
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		fmt.Fprintf(w, "<!doctype html><title>nixbook</title><p style='font:16px sans-serif'>%s", html.EscapeString(msg))
		select {
		case got <- q:
		default:
		}
	})}
	go srv.Serve(ln)
	defer srv.Shutdown(context.Background())

	link := authURL() + "?" + url.Values{
		"client_id": {c.ID}, "redirect_uri": {redirect}, "response_type": {"code"},
		"scope": {strings.Join(Scopes, " ")}, "access_type": {"offline"}, "prompt": {"consent"},
		"state": {state}, "code_challenge": {challenge}, "code_challenge_method": {"S256"},
	}.Encode()
	line, _ := json.Marshal(map[string]string{"authUrl": link})
	fmt.Fprintf(out, "%s\n", line)
	if f, ok := out.(*os.File); ok {
		f.Sync()
	}
	if openBrowser {
		if cmd := exec.Command("xdg-open", link); cmd.Start() == nil {
			go cmd.Wait()
		}
	}

	var q url.Values
	select {
	case q = <-got:
	case <-time.After(LoginTimeout):
		return none, core.Errorf("no answer from Google's page within 5 minutes")
	}
	if q.Get("code") == "" {
		return none, core.Errorf("Google refused: %s", q.Get("error"))
	}
	var r struct {
		Access    string `json:"access_token"`
		Refresh   string `json:"refresh_token"`
		ExpiresIn int    `json:"expires_in"`
		IDToken   string `json:"id_token"`
	}
	if err := core.Call("POST", tokenURL(), nil, url.Values{
		"grant_type": {"authorization_code"}, "code": {q.Get("code")}, "redirect_uri": {redirect},
		"client_id": {c.ID}, "client_secret": {c.Secret}, "code_verifier": {verifier},
	}, "", &r); err != nil {
		return none, err
	}
	if r.Refresh == "" {
		return none, core.Errorf("Google gave no refresh token: try again")
	}
	email := idTokenEmail(r.IDToken)
	name := email
	if name == "" {
		name = "Google"
	}
	a, err := registry.Save(registry.Account{Provider: "google", Name: name, Email: email})
	if err != nil {
		return a, err
	}
	return a, core.SecretSet(a.SecretKind(), &Token{
		Refresh: r.Refresh, Access: r.Access, Email: email,
		Expiry: float64(time.Now().Unix() + int64(expiresIn(r.ExpiresIn))),
	})
}

// Revoke asks Google to forget the account's token (it is being removed).
func Revoke(a registry.Account) {
	if t, err := LoadToken(a); err == nil && t != nil {
		_ = core.Call("POST", revokeURL(), nil, url.Values{"token": {t.Refresh}}, "", nil)
	}
}

// Connected says whether the account has a token (Google hasn't signed it
// out).
func Connected(a registry.Account) bool {
	t, err := LoadToken(a)
	return err == nil && t != nil
}
