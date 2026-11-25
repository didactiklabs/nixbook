#!/usr/bin/env bash
# qr-from-image.sh IMAGE [TITLE] [OPEN_LABEL] [COPY_LABEL]
#
# Looks for a QR code in a screenshot (zbarimg). When there is one, a
# notification shows what it holds, with "Open link" (a web link only: the
# default browser, through xdg-open) and "Copy text" (wl-copy). Nothing is
# opened or copied without a click. Prints nothing; exits 0 when no code is
# found or zbarimg is missing. The labels come translated from the shell.
img="$1"
title="${2:-QR code found}"
open_label="${3:-Open link}"
copy_label="${4:-Copy text}"

[ -s "$img" ] || exit 0
command -v zbarimg >/dev/null 2>&1 || exit 0

# Only QR codes (a screen's stripes can read as a 1D barcode), the first one
# (--oneshot: its text may hold newlines, a vCard or a Wi-Fi code).
code=$(zbarimg --quiet --raw --nodbus --oneshot -Sdisable -Sqrcode.enable "$img" 2>/dev/null) || exit 0
[ -n "$code" ] || exit 0

# The body is markup for the notification server: escape it, keep it short.
shown=$code
[ "${#shown}" -gt 300 ] && shown="${shown:0:300}…"
# (Quoted: an unquoted & in the replacement is the match, bash 5.2.)
shown=${shown//&/"&amp;"}
shown=${shown//</"&lt;"}
shown=${shown//>/"&gt;"}

actions=()
is_link=false
if [[ "$code" =~ ^https?://[^[:space:]]+$ ]]; then
    is_link=true
    actions+=(-A "open=$open_label")
fi
actions+=(-A "copy=$copy_label")

# Waits for the answer (the notification stays in the centre with its buttons).
answer=$(notify-send -a "$title" -i view-barcode-qr "${actions[@]}" "$title" "$shown")
case "$answer" in
    open) $is_link && xdg-open "$code" ;;
    copy) printf '%s' "$code" | wl-copy ;;
esac
exit 0
