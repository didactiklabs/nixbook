package core

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"
)

// Error is a failure to show the user as is.
type Error struct{ msg string }

func (e *Error) Error() string { return e.msg }

// Errorf makes an Error.
func Errorf(format string, a ...any) error { return &Error{fmt.Sprintf(format, a...)} }

// AuthError: no client, no account, or the provider signed the app out:
// sign in (again).
type AuthError struct{ msg string }

func (e *AuthError) Error() string { return e.msg }

// AuthErrorf makes an AuthError.
func AuthErrorf(format string, a ...any) error { return &AuthError{fmt.Sprintf(format, a...)} }

// APIError is a provider's answer to a failed call.
type APIError struct {
	Status  int
	Message string
	// Reason: the provider's status and reasons ("FAILED_PRECONDITION …"), or the
	// OAuth error code ("invalid_grant").
	Reason string
}

func (e *APIError) Error() string { return e.Message }

var client = &http.Client{Timeout: 30 * time.Second}

// MaxBody is the most of an answer read (a page of contacts or events is
// far less): a server can't fill the memory.
const MaxBody = 64 << 20

// ReadCapped reads an answer's body, at most MaxBody.
func ReadCapped(r io.Reader) ([]byte, error) {
	data, err := io.ReadAll(io.LimitReader(r, MaxBody+1))
	if err == nil && len(data) > MaxBody {
		err = errors.New("the answer is too large")
	}
	return data, err
}

// Getenv is os.Getenv (the endpoints and paths the tests move).
var Getenv = os.Getenv

// Endpoint is a provider's URL, or the one the tests give in env.
func Endpoint(env, fallback string) string {
	if v := Getenv(env); v != "" {
		return strings.TrimRight(v, "/")
	}
	return fallback
}

// Call sends a JSON body (or a form) and decodes the JSON answer into
// out (when not nil). Rate limited (429): one more try after the wait asked.
func Call(method, rawURL string, body any, form url.Values, token string, out any) error {
	for attempt := 0; ; attempt++ {
		var reader io.Reader
		contentType := ""
		if form != nil {
			reader = strings.NewReader(form.Encode())
			contentType = "application/x-www-form-urlencoded"
		} else if body != nil {
			data, err := json.Marshal(body)
			if err != nil {
				return err
			}
			reader = bytes.NewReader(data)
			contentType = "application/json"
		}
		req, err := http.NewRequest(method, rawURL, reader)
		if err != nil {
			return err
		}
		req.Header.Set("Accept", "application/json")
		if contentType != "" {
			req.Header.Set("Content-Type", contentType)
		}
		if token != "" {
			req.Header.Set("Authorization", "Bearer "+token)
		}
		resp, err := client.Do(req)
		if err != nil {
			var uerr *url.Error
			if errors.As(err, &uerr) {
				err = uerr.Err
			}
			return Errorf("can't reach %s: %v", host(rawURL), err)
		}
		data, err := ReadCapped(resp.Body)
		resp.Body.Close()
		if err != nil {
			return Errorf("can't reach %s: %v", host(rawURL), err)
		}
		if resp.StatusCode == http.StatusTooManyRequests && attempt == 0 {
			wait, _ := strconv.ParseFloat(resp.Header.Get("Retry-After"), 64)
			time.Sleep(time.Duration(min(max(wait, 2), 10) * float64(time.Second)))
			continue
		}
		if resp.StatusCode >= 300 {
			return apiError(resp.StatusCode, data)
		}
		if out == nil || len(bytes.TrimSpace(data)) == 0 {
			return nil
		}
		return json.Unmarshal(data, out)
	}
}

func host(rawURL string) string {
	if u, err := url.Parse(rawURL); err == nil && u.Host != "" {
		return u.Host
	}
	return "the server"
}

func apiError(status int, data []byte) error {
	var e struct {
		Error any    `json:"error"`
		Desc  string `json:"error_description"`
	}
	_ = json.Unmarshal(data, &e)
	switch v := e.Error.(type) {
	case map[string]any:
		msg, _ := v["message"].(string)
		reason, _ := v["status"].(string)
		if details, ok := v["details"].([]any); ok {
			for _, d := range details {
				if m, ok := d.(map[string]any); ok {
					if r, ok := m["reason"].(string); ok {
						reason += " " + r
					}
				}
			}
		}
		if msg == "" {
			msg = fmt.Sprintf("the server answered HTTP %d", status)
		}
		return &APIError{Status: status, Message: msg, Reason: reason}
	case string:
		msg := e.Desc
		if msg == "" {
			msg = v
		}
		return &APIError{Status: status, Message: msg, Reason: v}
	}
	return &APIError{Status: status, Message: fmt.Sprintf("the server answered HTTP %d", status)}
}
