#!/usr/bin/env sh


## check https://github.com/khanhas/spicetify-cli
ARTIST=$(playerctl -p spotify metadata artist)
TITLE=$(playerctl -p spotify metadata title)
STATUS=$(playerctl -p spotify status)
CLASS="custom-spotify"
ALT=$(playerctl -p spotify status)

printf '{"status":"%s","artist":"%s","title":"%s","class":"%s","alt":"%s"}\n' "$STATUS" "$ARTIST" "$TITLE" "$CLASS" "$ALT"
