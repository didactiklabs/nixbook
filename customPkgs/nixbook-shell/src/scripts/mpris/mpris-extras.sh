#!/usr/bin/env bash
# Optional MPRIS interfaces Quickshell doesn't expose, over busctl:
#   caps      <bus>        -> {"trackList":bool,"playlists":bool}
#   tracks    <bus>        -> [{"id","title","artist","length"}]   (TrackList, "up next")
#   goto      <bus> <id>   -> TrackList.GoTo
#   playlists <bus>        -> [{"id","name","icon"}]                (Playlists)
#   activate  <bus> <id>   -> Playlists.ActivatePlaylist
# Always exits 0 and prints JSON (empty on failure) so the shell degrades cleanly.
set -u
cmd="${1:-}"
bus="${2:-}"
obj=/org/mpris/MediaPlayer2
[ -n "$bus" ] || {
  echo '{}'
  exit 0
}

has_iface() {
  busctl --user introspect "$bus" "$obj" "$1" >/dev/null 2>&1
}

case "$cmd" in
caps)
  tl=false pl=false
  if has_iface org.mpris.MediaPlayer2.TrackList; then tl=true; fi
  if has_iface org.mpris.MediaPlayer2.Playlists; then
    n=$(busctl --user --json=short get-property "$bus" "$obj" org.mpris.MediaPlayer2.Playlists PlaylistCount 2>/dev/null | jq -r '.data // 0')
    [ "${n:-0}" -gt 0 ] 2>/dev/null && pl=true
  fi
  printf '{"trackList":%s,"playlists":%s}\n' "$tl" "$pl"
  ;;
tracks)
  ids=$(busctl --user --json=short get-property "$bus" "$obj" org.mpris.MediaPlayer2.TrackList Tracks 2>/dev/null | jq -r '.data[]?' | head -n 50)
  [ -n "$ids" ] || {
    echo '[]'
    exit 0
  }
  # shellcheck disable=SC2086
  busctl --user --json=short call "$bus" "$obj" org.mpris.MediaPlayer2.TrackList GetTracksMetadata ao \
    "$(wc -l <<<"$ids")" $ids 2>/dev/null |
    jq -c '[.data[0][]? | {
      id: (.["mpris:trackid"].data // ""),
      title: (.["xesam:title"].data // ""),
      artist: ((.["xesam:artist"].data // []) | join(", ")),
      length: ((.["mpris:length"].data // 0) / 1000000 | floor)
    } | select(.id != "")]' 2>/dev/null || echo '[]'
  ;;
goto)
  busctl --user call "$bus" "$obj" org.mpris.MediaPlayer2.TrackList GoTo o "${3:-}" >/dev/null 2>&1
  echo '{}'
  ;;
playlists)
  busctl --user --json=short call "$bus" "$obj" org.mpris.MediaPlayer2.Playlists GetPlaylists uusb 0 100 Alphabetical false 2>/dev/null |
    jq -c '[.data[0][]? | {id: .[0], name: .[1], icon: .[2]}]' 2>/dev/null || echo '[]'
  ;;
activate)
  busctl --user call "$bus" "$obj" org.mpris.MediaPlayer2.Playlists ActivatePlaylist o "${3:-}" >/dev/null 2>&1
  echo '{}'
  ;;
*)
  echo '{}'
  ;;
esac
