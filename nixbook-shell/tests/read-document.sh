#!/usr/bin/env bash
# Tests for read_document (scripts/desktop-mcp.py): a document's text for
# DAI ("summarize this PDF"), on fixtures with stub poppler and tesseract:
#   - a PDF read page by page, the first 30 by default, `pages` ranges, the
#     next pages named when it stops;
#   - scanned pages (no text layer) read with OCR, at most 10 per call,
#     `ocr: false` skipping them;
#   - docx, odt and text files; secrets blacked out;
#   - what is refused: outside the home, hidden folders, files named like
#     secrets, unknown types, bad page ranges.
# Needs bash, python3 and jq. Run: bash tests/read-document.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

failures=0
pass() { echo "ok   - $1"; }
fail() {
  echo "FAIL - $1" >&2
  [ $# -lt 2 ] || printf '%s\n' "$2" | sed 's/^/       /' >&2
  failures=$((failures + 1))
}
expect_contains() {
  case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" "expected to contain: $3"$'\n'"actual: $2" ;; esac
}
expect_not_contains() {
  case "$2" in *"$3"*) fail "$1" "unexpected: $3"$'\n'"in: $2" ;; *) pass "$1" ;; esac
}

home="$tmp/home"
mkdir -p "$home/Downloads" "$home/.private" "$tmp/cfg/nixbook-shell" "$tmp/run" "$tmp/bin" "$tmp/state"
export HOME="$home" XDG_STATE_HOME="$tmp/state" XDG_CONFIG_HOME="$tmp/cfg" XDG_RUNTIME_DIR="$tmp/run"
export XDG_DATA_HOME="$tmp/data" XDG_CACHE_HOME="$tmp/cache" PATH="$tmp/bin:$PATH"
unset NIXBOOK_DESKTOP_MCP_CONFIG
echo '{"policies": {"ai": 1}}' >"$tmp/cfg/nixbook-shell/config.json"
dm() { python3 -I "$root/scripts/desktop-mcp.py" "$@"; }
read_doc() { dm call read_document "$1" 2>&1 || true; }

# Stub poppler: the page count is in the file ("pages=N"); a file named
# scan* has no text layer on its even pages.
cat >"$tmp/bin/pdfinfo" <<'EOF'
#!/usr/bin/env bash
grep -q '^%PDF' "$1" || { echo "Syntax Error: not a PDF" >&2; exit 1; }
echo "Pages:          $(sed -n 's/^pages=//p' "$1")"
EOF
cat >"$tmp/bin/pdftotext" <<'EOF'
#!/usr/bin/env bash
page=$3 file="${*: -2:1}"
case "$(basename "$file")" in
scan*) [ $((page % 2)) = 1 ] && echo "Typed text of page $page, long enough to count" ;;
*) echo "Text of page $page, a full page of words" ;;
esac
exit 0
EOF
cat >"$tmp/bin/pdftoppm" <<'EOF'
#!/usr/bin/env bash
echo "image of page $2"
EOF
cat >"$tmp/bin/tesseract" <<'EOF'
#!/usr/bin/env bash
echo "tesseract $*" >>"$TESS_CALLS"
echo "OCR: $(cat)"
EOF
chmod +x "$tmp/bin/"*
export TESS_CALLS="$tmp/tess"
: >"$TESS_CALLS"

printf '%%PDF-1.4\npages=45\n' >"$home/Downloads/report.pdf"
printf '%%PDF-1.4\npages=40\n' >"$home/Downloads/scan.pdf"

out=$(read_doc '{"path": "~/Downloads/report.pdf"}')
expect_contains "pdf: the page count" "$out" "PDF, 45 page(s); pages 1–30 below"
expect_contains "pdf: page text" "$out" $'--- page 30 ---\nText of page 30'
expect_not_contains "pdf: the first 30 pages by default" "$out" "page 31 ---"
expect_contains "pdf: the next pages named" "$out" 'call again with pages "31-"'
out=$(read_doc '{"path": "~/Downloads/report.pdf", "pages": "44-"}')
expect_contains "pdf: an open range" "$out" "pages 44–45 below"
expect_not_contains "pdf: nothing more to read" "$out" "call again"
out=$(read_doc '{"path": "~/Downloads/report.pdf", "pages": "3"}')
expect_contains "pdf: one page" "$out" $'--- page 3 ---\nText of page 3'
expect_contains "pdf: a page past the end refused" "$(read_doc '{"path": "~/Downloads/report.pdf", "pages": "46"}')" "45 page(s)"
expect_contains "pdf: a malformed range refused" "$(read_doc '{"path": "~/Downloads/report.pdf", "pages": "a-b"}')" "must look like"

: >"$TESS_CALLS"
out=$(read_doc '{"path": "~/Downloads/scan.pdf"}')
expect_contains "scan: typed pages from their text" "$out" $'--- page 1 ---\nTyped text of page 1, long enough'
expect_contains "scan: a scanned page through OCR" "$out" $'--- page 2 ---\nOCR: image of page 2'
expect_contains "scan: OCR in the configured languages" "$(head -n 1 "$TESS_CALLS")" "-l eng"
expect_contains "scan: the OCR pages said" "$out" "pages read with OCR (eng): 2, 4, 6"
n=$(grep -c . "$TESS_CALLS")
if [ "$n" = 10 ]; then pass "scan: at most 10 OCR pages per call"; else fail "scan: at most 10 OCR pages per call" "$n"; fi
expect_contains "scan: stops at the 11th scanned page" "$out" 'call again with pages "22-"'
: >"$TESS_CALLS"
out=$(read_doc '{"path": "~/Downloads/scan.pdf", "pages": "1-4", "ocr": false}')
expect_contains "scan: ocr false leaves scanned pages" "$out" $'--- page 2 ---\n(no text)'
if [ -s "$TESS_CALLS" ]; then fail "scan: ocr false runs no OCR"; else pass "scan: ocr false runs no OCR"; fi

python3 - "$home/Downloads" <<'EOF'
import sys, zipfile
d = sys.argv[1]
with zipfile.ZipFile(f"{d}/letter.docx", "w") as z:
    z.writestr("word/document.xml", "<w:document><w:body><w:p><w:r><w:t>Dear Ana,</w:t></w:r></w:p>"
               "<w:p><w:r><w:t>Fish &amp; chips at noon.</w:t></w:r></w:p></w:body></w:document>")
with zipfile.ZipFile(f"{d}/minutes.odt", "w") as z:
    z.writestr("content.xml", "<office:text><text:p>Minutes of the meeting</text:p><text:p>Budget approved</text:p></office:text>")
EOF
out=$(read_doc '{"path": "~/Downloads/letter.docx"}')
expect_contains "docx: paragraphs as lines" "$out" $'Dear Ana,\nFish & chips at noon.'
out=$(read_doc '{"path": "~/Downloads/minutes.odt"}')
expect_contains "odt: paragraphs as lines" "$out" $'Minutes of the meeting\nBudget approved'
printf 'notes\napi_key = sk-ant-abcdefghijklmnopqrstuvwx\n' >"$home/Downloads/notes.md"
out=$(read_doc '{"path": "~/Downloads/notes.md"}')
expect_contains "text: read" "$out" "notes"
expect_not_contains "text: secrets blacked out" "$out" "sk-ant-abcdefghijklmnopqrstuvwx"

printf '%%PDF-1.4\npages=1\n' >"$home/.private/statement.pdf"
expect_contains "refused: a hidden folder" "$(read_doc '{"path": "~/.private/statement.pdf"}')" "hidden folder"
expect_contains "refused: outside the home" "$(read_doc '{"path": "/etc/hostname"}')" "isn't in the user's home"
printf '%%PDF-1.4\npages=1\n' >"$home/Downloads/recovery-codes.pdf"
expect_contains "refused: named like a secret" "$(read_doc '{"path": "~/Downloads/recovery-codes.pdf"}')" "refused"
printf 'x' >"$home/Downloads/song.mp3"
expect_contains "refused: not a document" "$(read_doc '{"path": "~/Downloads/song.mp3"}')" "not .mp3"
printf 'not a pdf' >"$home/Downloads/broken.pdf"
expect_contains "a broken PDF said" "$(read_doc '{"path": "~/Downloads/broken.pdf"}')" "isn't a readable PDF"

spec=$(dm tools | jq -c '.[] | select(.name == "read_document")')
expect_contains "listed, read-only" "$spec" '"readOnlyHint":true'
expect_contains "loaded up front" "$spec" '"anthropic/alwaysLoad":true'

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all read_document tests passed"
