# shellcheck shell=bash
# wl-copy that keeps text as text (wl-copy.nix puts it before wl-clipboard).
#
# Without --type, wl-copy guesses the content's MIME type, and its guess can
# make text unpasteable: a command starting with `v=$(…)` is offered as
# application/sdp only (a WebRTC session description starts with "v=0"), so
# a text field asking for text/plain gets nothing. Claude Code, cliphist's
# history and scripts all copy through a bare `wl-copy`. Here: text given as
# arguments, or stdin that isn't binary, is offered as text/plain; binary
# data (an image) keeps wl-copy's guess; a type given, --clear, --help and
# --version go to wl-copy unchanged.
#
# NB_WL_COPY (the real wl-copy) and NB_FILE (file) are set by wl-copy.nix.

pos=0
skip=0
ended=0
for a in "$@"; do
  if [ "$skip" = 1 ]; then
    skip=0
    continue
  fi
  if [ "$ended" = 1 ]; then
    pos=1
    continue
  fi
  case $a in
  --) ended=1 ;;
  --type | --type=* | --clear | --help | --version) exec "$NB_WL_COPY" "$@" ;;
  --seat) skip=1 ;;
  --*) ;;
  -?*)
    flags=${a#-}
    case $flags in *[tchv]*) exec "$NB_WL_COPY" "$@" ;; esac
    case $flags in *s) skip=1 ;; esac
    ;;
  *) pos=1 ;;
  esac
done

if [ "$pos" = 1 ]; then
  exec "$NB_WL_COPY" --type "text/plain;charset=utf-8" "$@"
fi

tmp=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/wl-copy.XXXXXX") || exec "$NB_WL_COPY" "$@"
trap 'rm -f "$tmp"' EXIT
cat >"$tmp"
case $("$NB_FILE" -b --mime-encoding "$tmp") in
binary) ;;
utf-8 | us-ascii) set -- --type "text/plain;charset=utf-8" "$@" ;;
*) set -- --type text/plain "$@" ;;
esac
# wl-copy reads all of stdin before it forks to serve the clipboard.
"$NB_WL_COPY" "$@" <"$tmp"
