package google

import (
	"encoding/base64"
	"io"
	"mime"
	"mime/multipart"
	"mime/quotedprintable"
	"net/mail"
	"strings"
	"testing"
)

func TestHTMLText(t *testing.T) {
	got := HTMLText(`<html><head><style>p{color:red}</style><title>x</title></head><body>
<p>Hello&nbsp;<b>Victor</b>,</p><script>alert(1)</script>
<ul><li>one</li><li>two</li></ul>
<p>See <a href="https://example.com/a">the page</a> or <a href="mailto:x@y">mail</a>.</p><br>Bye &amp; thanks</body></html>`)
	want := "Hello Victor,\n\n- one\n- two\n\nSee the page (https://example.com/a) or mail.\n\nBye & thanks"
	if got != want {
		t.Fatalf("got %q\nwant %q", got, want)
	}
}

func TestTrimQuoted(t *testing.T) {
	cases := []struct{ in, want string }{
		{"Sounds good.\n\nOn Mon, 3 Nov 2026 at 10:00, Ana <ana@x.org> wrote:\n> Lunch?\n> Tomorrow", "Sounds good."},
		{"Oui !\n\nLe lun. 3 nov. 2026 à 10:00, Ana <ana@x.org> a\nécrit :\n> Déjeuner ?", "Oui !"},
		{"Ok\n\n-----Original Message-----\nFrom: Ana\nSent: Monday", "Ok"},
		{"Ok\n\nFrom: Ana <ana@x.org>\nSent: Monday\nTo: me\n\nhello", "Ok"},
		{"> quoted first\nmy answer\n> more", "> quoted first\nmy answer"},
		{"Plain message", "Plain message"},
	}
	for _, c := range cases {
		if got, _ := TrimQuoted(c.in); got != c.want {
			t.Errorf("TrimQuoted(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestPartTextCharset(t *testing.T) {
	p := gPart{MimeType: "text/plain", Headers: []gHeader{{"Content-Type", "text/plain; charset=ISO-8859-1"}}}
	p.Body.Data = base64.RawURLEncoding.EncodeToString([]byte("caf\xe9"))
	if got := partText(p); got != "café" {
		t.Fatalf("got %q", got)
	}
}

func TestMessageBodyPrefersPlain(t *testing.T) {
	enc := func(s string) string { return base64.RawURLEncoding.EncodeToString([]byte(s)) }
	m := gMessage{Payload: gPart{MimeType: "multipart/mixed", Parts: []gPart{
		{MimeType: "multipart/alternative", Parts: []gPart{
			{MimeType: "text/plain"}, {MimeType: "text/html"},
		}},
		{PartID: "1", MimeType: "application/pdf", Filename: "invoice.pdf"},
	}}}
	m.Payload.Parts[0].Parts[0].Body.Data = enc("plain  text\r\n\r\n\r\n\r\nend")
	m.Payload.Parts[0].Parts[1].Body.Data = enc("<p>html</p>")
	m.Payload.Parts[1].Body.AttachmentID, m.Payload.Parts[1].Body.Size = "att", 1234
	text, files := messageBody(m)
	if text != "plain text\n\nend" || len(files) != 1 || files[0].Name != "invoice.pdf" || files[0].Part != "1" {
		t.Fatalf("got %q %+v", text, files)
	}
}

func TestOutgoingRaw(t *testing.T) {
	o := outgoing{
		From:    &mail.Address{Address: "me@example.com"},
		To:      []*mail.Address{{Name: "Ana Pérez", Address: "ana@x.org"}},
		Bcc:     []*mail.Address{{Address: "b@x.org"}},
		Subject: "Réunion demain", Body: "Ligne une\nLigne deux — fin",
		InReplyTo: "<a@x>", References: "<z@x> <a@x>",
		Files: []outFile{{Name: "notes été.txt", Data: []byte("hello")}},
	}
	msg, err := mail.ReadMessage(strings.NewReader(string(o.raw())))
	if err != nil {
		t.Fatal(err)
	}
	dec := new(mime.WordDecoder)
	if s, _ := dec.DecodeHeader(msg.Header.Get("Subject")); s != "Réunion demain" {
		t.Errorf("subject %q", s)
	}
	if to, _ := msg.Header.AddressList("To"); len(to) != 1 || to[0].Name != "Ana Pérez" {
		t.Errorf("to %v", to)
	}
	if msg.Header.Get("Bcc") != "<b@x.org>" || msg.Header.Get("In-Reply-To") != "<a@x>" {
		t.Errorf("headers %v", msg.Header)
	}
	_, params, _ := mime.ParseMediaType(msg.Header.Get("Content-Type"))
	r := multipart.NewReader(msg.Body, params["boundary"])
	p, _ := r.NextPart()
	body, _ := io.ReadAll(quotedprintable.NewReader(p))
	if string(body) != "Ligne une\r\nLigne deux — fin" {
		t.Errorf("body %q", body)
	}
	p, _ = r.NextPart()
	if p.FileName() != "notes été.txt" {
		t.Errorf("file name %q", p.FileName())
	}
	data, _ := io.ReadAll(p)
	if got, _ := base64.StdEncoding.DecodeString(strings.ReplaceAll(string(data), "\r\n", "")); string(got) != "hello" {
		t.Errorf("file %q", data)
	}
}

func TestFilterCriteria(t *testing.T) {
	c, err := filterCriteria(map[string]any{"from": "news@shop.com", "notQuery": "invoice", "larger": "5M"})
	if err != nil {
		t.Fatal(err)
	}
	if q := criteriaQuery(c); q != "from:(news@shop.com) -(invoice) larger:5242880" {
		t.Errorf("query %q", q)
	}
	if f := friendlyCriteria(c); f["larger"] != "5M" || f["notQuery"] != "invoice" {
		t.Errorf("friendly %v", f)
	}
	if _, err := filterCriteria(map[string]any{"excludeChats": true}); err == nil {
		t.Error("criteria without a condition accepted")
	}
	if _, err := filterCriteria(map[string]any{"from": "a", "larger": "1M", "smaller": "2M"}); err == nil {
		t.Error("larger and smaller accepted together")
	}
}

func TestSafeFileName(t *testing.T) {
	for in, want := range map[string]string{"../../.bashrc": "bashrc", "a\x00b.pdf": "ab.pdf", "C:\\x\\y.doc": "y.doc", "": "attachment"} {
		if got := safeFileName(in); got != want {
			t.Errorf("safeFileName(%q) = %q, want %q", in, got, want)
		}
	}
}
