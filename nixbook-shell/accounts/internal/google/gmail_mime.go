package google

import (
	"bytes"
	"encoding/base64"
	"fmt"
	"io"
	"mime"
	"mime/multipart"
	"mime/quotedprintable"
	"net/http"
	"net/mail"
	"net/textproto"
	"path/filepath"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"

	"golang.org/x/net/html"
	"golang.org/x/text/encoding/htmlindex"
)

// What Gmail's API gives of a message (format=full or metadata): the MIME
// tree with each part's body decoded from its transfer encoding, base64url.
type gHeader struct {
	Name  string `json:"name"`
	Value string `json:"value"`
}

type gPart struct {
	PartID   string    `json:"partId"`
	MimeType string    `json:"mimeType"`
	Filename string    `json:"filename"`
	Headers  []gHeader `json:"headers"`
	Body     struct {
		Size         int    `json:"size"`
		Data         string `json:"data"`
		AttachmentID string `json:"attachmentId"`
	} `json:"body"`
	Parts []gPart `json:"parts"`
}

type gMessage struct {
	ID           string   `json:"id"`
	ThreadID     string   `json:"threadId"`
	LabelIDs     []string `json:"labelIds"`
	Snippet      string   `json:"snippet"`
	InternalDate string   `json:"internalDate"`
	Payload      gPart    `json:"payload"`
}

func (p gPart) header(name string) string {
	for _, h := range p.Headers {
		if strings.EqualFold(h.Name, name) {
			return h.Value
		}
	}
	return ""
}

func (m gMessage) time() time.Time {
	var ms int64
	fmt.Sscan(m.InternalDate, &ms)
	return time.UnixMilli(ms)
}

func (m gMessage) has(label string) bool {
	for _, l := range m.LabelIDs {
		if l == label {
			return true
		}
	}
	return false
}

func decodeB64(s string) ([]byte, error) {
	s = strings.TrimRight(s, "=")
	if b, err := base64.RawURLEncoding.DecodeString(s); err == nil {
		return b, nil
	}
	return base64.RawStdEncoding.DecodeString(s)
}

// partText is a text part's body as UTF-8, from its declared charset.
func partText(p gPart) string {
	data, err := decodeB64(p.Body.Data)
	if err != nil {
		return ""
	}
	_, params, _ := mime.ParseMediaType(p.header("Content-Type"))
	if cs := strings.ToLower(params["charset"]); cs != "" && cs != "utf-8" && cs != "us-ascii" {
		if enc, err := htmlindex.Get(cs); err == nil {
			if out, err := enc.NewDecoder().Bytes(data); err == nil {
				data = out
			}
		}
	}
	return strings.ToValidUTF8(string(data), "�")
}

// Attachment is a file a message carries, by its part (Gmail's attachment
// ids change from one fetch to the next; a part's id doesn't).
type Attachment struct {
	Part string `json:"part"`
	Name string `json:"name"`
	Mime string `json:"mime"`
	Size int    `json:"size"`
}

// walk visits every part, depth first.
func walk(p gPart, visit func(gPart)) {
	visit(p)
	for _, c := range p.Parts {
		walk(c, visit)
	}
}

// isAttachment: a part with a file name, or said to be an attachment.
func isAttachment(p gPart) bool {
	if p.Filename != "" {
		return true
	}
	d, _, _ := mime.ParseMediaType(p.header("Content-Disposition"))
	return d == "attachment"
}

// messageBody is a message's text (its plain part, else its HTML one made
// plain) and its attachments.
func messageBody(m gMessage) (text string, attachments []Attachment) {
	plain, htmlBody := "", ""
	attachments = []Attachment{}
	walk(m.Payload, func(p gPart) {
		if isAttachment(p) {
			if p.Body.AttachmentID != "" || p.Body.Data != "" {
				name := p.Filename
				if name == "" {
					name = "attachment"
				}
				attachments = append(attachments, Attachment{Part: p.PartID, Name: name, Mime: p.MimeType, Size: p.Body.Size})
			}
			return
		}
		switch strings.ToLower(p.MimeType) {
		case "text/plain":
			if plain == "" {
				plain = partText(p)
			}
		case "text/html":
			if htmlBody == "" {
				htmlBody = partText(p)
			}
		}
	})
	if strings.TrimSpace(plain) != "" {
		return tidyText(plain), attachments
	}
	return HTMLText(htmlBody), attachments
}

var (
	blankLines = regexp.MustCompile(`\n{3,}`)
	spaces     = regexp.MustCompile(`[ \t\f\v\x{00a0}\x{200b}\x{200c}\x{feff}]+`)
)

// tidyText: lines trimmed, at most one blank line in a row.
func tidyText(s string) string {
	s = strings.ReplaceAll(strings.ReplaceAll(s, "\r\n", "\n"), "\r", "\n")
	lines := strings.Split(s, "\n")
	for i, l := range lines {
		lines[i] = strings.TrimSpace(spaces.ReplaceAllString(l, " "))
	}
	return strings.TrimSpace(blankLines.ReplaceAllString(strings.Join(lines, "\n"), "\n\n"))
}

// HTMLText is an HTML mail as plain text: no styles, scripts or hidden
// head; blocks on their own lines, list items marked, links' addresses
// after their text.
func HTMLText(src string) string {
	z := html.NewTokenizer(strings.NewReader(src))
	var b strings.Builder
	skip := 0
	var hrefs []string
	for {
		tt := z.Next()
		switch tt {
		case html.ErrorToken:
			return tidyText(b.String())
		case html.TextToken:
			if skip == 0 {
				b.WriteString(spaces.ReplaceAllString(strings.ReplaceAll(string(z.Text()), "\n", " "), " "))
			}
		case html.StartTagToken, html.EndTagToken, html.SelfClosingTagToken:
			name, hasAttr := z.TagName()
			tag := string(name)
			switch tag {
			case "script", "style", "head", "title", "noscript", "template", "svg":
				if tt == html.StartTagToken {
					skip++
				} else if tt == html.EndTagToken && skip > 0 {
					skip--
				}
				continue
			}
			if skip > 0 {
				continue
			}
			switch tag {
			case "br":
				b.WriteString("\n")
			case "p", "div", "tr", "table", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "section",
				"article", "header", "footer", "ul", "ol", "center":
				b.WriteString("\n")
			case "hr":
				b.WriteString("\n---\n")
			case "li":
				if tt == html.StartTagToken {
					b.WriteString("\n- ")
				}
			case "td", "th":
				if tt == html.EndTagToken {
					b.WriteString(" ")
				}
			case "a":
				if tt == html.StartTagToken {
					href := ""
					for hasAttr {
						var k, v []byte
						k, v, hasAttr = z.TagAttr()
						if string(k) == "href" {
							href = strings.TrimSpace(string(v))
						}
					}
					hrefs = append(hrefs, href)
				} else if tt == html.EndTagToken && len(hrefs) > 0 {
					href := hrefs[len(hrefs)-1]
					hrefs = hrefs[:len(hrefs)-1]
					if strings.HasPrefix(href, "http://") || strings.HasPrefix(href, "https://") {
						if len(href) > 500 {
							href = href[:500] + "…"
						}
						b.WriteString(" (" + href + ")")
					}
				}
			}
		}
	}
}

var (
	attribution = regexp.MustCompile(`(?is)^(on\b.{4,200}\bwrote:|le\b.{4,200}\ba écrit\s?:|am\b.{4,200}\bschrieb.{0,40}:|vào\b.{4,200}\bđã viết:|.{4,200}<[^>\s]+@[^>\s]+>\s*(wrote|a écrit|schrieb)\s?:)$`)
	outlookCut  = regexp.MustCompile(`(?i)^(-{2,}\s*(original message|message d'origine|ursprüngliche nachricht|forwarded message|message transféré)\s*-{2,}|_{10,})$`)
	outlookFrom = regexp.MustCompile(`(?i)^(from|de|von|từ)\s?:\s`)
	outlookNext = regexp.MustCompile(`(?i)^(sent|date|envoyé|gesendet|đã gửi|to|à|an)\s?:\s`)
)

// TrimQuoted cuts the earlier messages a reply quotes at its end (they are
// the thread's other messages): "> …" lines and the "On … wrote:" before
// them, or an Outlook "From: … Sent: …" block.
func TrimQuoted(text string) (string, bool) {
	lines := strings.Split(text, "\n")
	cut := -1
	for i, l := range lines {
		t := strings.TrimSpace(l)
		if outlookCut.MatchString(t) {
			cut = i
			break
		}
		if outlookFrom.MatchString(t) && i+1 < len(lines) && (outlookNext.MatchString(strings.TrimSpace(lines[i+1])) ||
			i+2 < len(lines) && outlookNext.MatchString(strings.TrimSpace(lines[i+2]))) {
			cut = i
			break
		}
		if strings.HasPrefix(t, ">") {
			rest := true
			for _, r := range lines[i:] {
				if r = strings.TrimSpace(r); r != "" && !strings.HasPrefix(r, ">") {
					rest = false
					break
				}
			}
			if rest {
				cut = i
				// The attribution before it, on one line or wrapped on two.
				j := i - 1
				for j >= 0 && strings.TrimSpace(lines[j]) == "" {
					j--
				}
				if j >= 0 && attribution.MatchString(strings.TrimSpace(lines[j])) {
					cut = j
				} else if j >= 1 && attribution.MatchString(strings.TrimSpace(lines[j-1])+" "+strings.TrimSpace(lines[j])) {
					cut = j - 1
				}
				break
			}
		}
	}
	if cut <= 0 {
		return text, false
	}
	return strings.TrimSpace(strings.Join(lines[:cut], "\n")), true
}

// Clip is s cut to at most n characters.
func Clip(s string, n int) string {
	if utf8.RuneCountInString(s) <= n {
		return s
	}
	r := []rune(s)
	return string(r[:n]) + "…"
}

// outgoing is a message to send or keep as a draft.
type outgoing struct {
	From                  *mail.Address
	To, Cc, Bcc           []*mail.Address
	Subject, Body         string
	InReplyTo, References string
	Files                 []outFile
}

type outFile struct {
	Name string
	Data []byte
}

func joinAddresses(list []*mail.Address) string {
	out := make([]string, len(list))
	for i, a := range list {
		out[i] = a.String()
	}
	return strings.Join(out, ", ")
}

func crlf(s string) string {
	s = strings.ReplaceAll(strings.ReplaceAll(s, "\r\n", "\n"), "\r", "\n")
	return strings.ReplaceAll(s, "\n", "\r\n")
}

// raw is the message as RFC 5322 (Gmail takes it whole, Bcc included, and
// drops the Bcc header when sending).
func (o outgoing) raw() []byte {
	var b bytes.Buffer
	h := func(k, v string) {
		if v != "" {
			fmt.Fprintf(&b, "%s: %s\r\n", k, v)
		}
	}
	if o.From != nil {
		h("From", o.From.String())
	}
	h("To", joinAddresses(o.To))
	h("Cc", joinAddresses(o.Cc))
	h("Bcc", joinAddresses(o.Bcc))
	h("Subject", mime.QEncoding.Encode("utf-8", o.Subject))
	h("Date", time.Now().Format(time.RFC1123Z))
	h("In-Reply-To", o.InReplyTo)
	h("References", o.References)
	h("MIME-Version", "1.0")
	textPart := func(w io.Writer) {
		qp := quotedprintable.NewWriter(w)
		qp.Write([]byte(crlf(o.Body)))
		qp.Close()
	}
	if len(o.Files) == 0 {
		h("Content-Type", "text/plain; charset=utf-8")
		h("Content-Transfer-Encoding", "quoted-printable")
		b.WriteString("\r\n")
		textPart(&b)
		return b.Bytes()
	}
	mw := multipart.NewWriter(&b)
	h("Content-Type", "multipart/mixed; boundary="+mw.Boundary())
	b.WriteString("\r\n")
	w, _ := mw.CreatePart(textproto.MIMEHeader{
		"Content-Type":              {"text/plain; charset=utf-8"},
		"Content-Transfer-Encoding": {"quoted-printable"},
	})
	textPart(w)
	for _, f := range o.Files {
		kind := mime.TypeByExtension(strings.ToLower(filepath.Ext(f.Name)))
		if kind == "" {
			kind = http.DetectContentType(f.Data)
		}
		w, _ := mw.CreatePart(textproto.MIMEHeader{
			"Content-Type":              {mime.FormatMediaType(strings.SplitN(kind, ";", 2)[0], map[string]string{"name": f.Name})},
			"Content-Disposition":       {mime.FormatMediaType("attachment", map[string]string{"filename": f.Name})},
			"Content-Transfer-Encoding": {"base64"},
		})
		enc := base64.StdEncoding.EncodeToString(f.Data)
		for len(enc) > 76 {
			io.WriteString(w, enc[:76]+"\r\n")
			enc = enc[76:]
		}
		io.WriteString(w, enc+"\r\n")
	}
	mw.Close()
	return b.Bytes()
}
