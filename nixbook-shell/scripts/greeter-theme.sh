#!/usr/bin/env bash
# The login screen's (ReGreet, greeter.nix) look, from nixbook-shell's
# settings: writes $NB_OUT/regreet.css and, with NB_COPY_BACKGROUND=1,
# $NB_OUT/background (the login screen wallpaper, readable by the greeter).
#
# Run by greeter.nix twice: at build time from the settings set in Nix (the
# fallback theme, no wallpaper copy), and as the user by the
# nixbook-shell-greeter-theme service whenever the shell's settings or
# wallpaper palette change (the live theme). Everything taken from the
# settings is validated: this runs as the user and the greeter loads the
# result.
#
# Env: NB_OUT, NB_PALETTES (Persona palettes, JSON), NB_TEXTURES (Persona art
# dir); optional NB_CONFIG (config.json), NB_COLORS (the shell's generated
# Material palette), NB_DEFAULT_BACKGROUND (the NixOS option's wallpaper),
# NB_COPY_BACKGROUND=1.
set -euo pipefail

: "${NB_OUT:?}" "${NB_PALETTES:?}" "${NB_TEXTURES:?}"
config="${NB_CONFIG:-}"
colors="${NB_COLORS:-}"
[ -n "$config" ] && [ -s "$config" ] && jq -e 'type == "object"' "$config" >/dev/null 2>&1 || config=""
[ -n "$colors" ] && [ -s "$colors" ] && jq -e 'type == "object"' "$colors" >/dev/null 2>&1 || colors=""

# The settings the theme depends on, with the shell's defaults
# (Config.qml / Persona.qml).
theme=$(jq -n \
  --slurpfile palettes "$NB_PALETTES" \
  --slurpfile cfgs "${config:-/dev/null}" \
  --slurpfile m3s "${colors:-/dev/null}" '
  def color($v; $fallback):
    if ($v | type) == "string" and ($v | test("^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$")) then $v else $fallback end;
  def font($v; $fallback):
    if ($v | type) == "string" and ($v | test("^[A-Za-z0-9 _-]{1,64}$")) then $v else $fallback end;

  ($cfgs[0] // {}) as $cfg
  | ($m3s[0] // {}) as $m3
  | ($cfg.appearance.persona // {}) as $p
  | ($p.enable == true) as $persona
  | (if (["p5", "p3r", "p4"] | index($p.variant)) != null then $p.variant else "p5" end) as $variant
  | ($palettes[0][$variant]) as $spec
  # Appearance.qml m3colors defaults, when the shell has generated no palette.
  | {
      background: "#141313", surface_container_low: "#1c1b1c", surface_container: "#201f20",
      surface_container_high: "#2b2a2a", surface_container_highest: "#353434",
      on_surface: "#e6e1e1", on_surface_variant: "#cbc5ca", outline: "#948f94",
      outline_variant: "#49464a", primary: "#cbc4cb", on_primary: "#322f34",
      primary_container: "#2d2a2f", on_primary_container: "#bcb6bc",
      secondary_container: "#4d4b4d", on_secondary_container: "#ece6e9",
      error: "#ffb4ab", error_container: "#93000a", on_error_container: "#ffdad6"
    } as $d
  | def m3($k): color($m3[$k]; $d[$k]);
  (if $persona and ($p.palette != false) then
     {
       bg: $spec.background, surface1: $spec.surface1, surface2: $spec.surface2,
       surface3: $spec.surface3, surface4: $spec.surface4,
       on_surface: $spec.onSurface, on_surface_variant: $spec.onSurfaceVariant,
       outline: $spec.outline, outline_variant: $spec.outlineVariant,
       primary: $spec.primary, on_primary: $spec.onPrimary,
       primary_container: $spec.primaryContainer, on_primary_container: $spec.onPrimaryContainer,
       secondary_container: $spec.secondaryContainer, on_secondary_container: $spec.onSecondaryContainer,
       error: $spec.error, error_container: $spec.errorContainer, on_error_container: $spec.onErrorContainer,
       frame: $spec.frame, frame_border: $spec.frameBorder, shadow: $spec.shadow, stripe: $spec.stripe,
       edge: ($spec.edge // $spec.frameBorder)
     }
   else
     {
       bg: m3("background"), surface1: m3("surface_container_low"), surface2: m3("surface_container"),
       surface3: m3("surface_container_high"), surface4: m3("surface_container_highest"),
       on_surface: m3("on_surface"), on_surface_variant: m3("on_surface_variant"),
       outline: m3("outline"), outline_variant: m3("outline_variant"),
       primary: m3("primary"), on_primary: m3("on_primary"),
       primary_container: m3("primary_container"), on_primary_container: m3("on_primary_container"),
       secondary_container: m3("secondary_container"), on_secondary_container: m3("on_secondary_container"),
       error: m3("error"), error_container: m3("error_container"), on_error_container: m3("on_error_container"),
       frame: m3("surface_container"), frame_border: m3("outline_variant"), shadow: "#000000",
       stripe: m3("primary"), edge: m3("outline_variant")
     }
   end) as $colors
  | {
      colors: ($colors | with_entries(.value = color(.value; "#808080"))),
      persona: $persona,
      variant: $variant,
      shapes: ($persona and ($p.shapes != false)),
      halftone: ($persona and ($p.halftone != false)),
      titleFont: (if $persona and ($p.fonts != false) then "Oswald"
                  else font($cfg.appearance.fonts.title; "Roboto") end),
      mainFont: font($cfg.appearance.fonts.main; "Roboto"),
      # Persona.qml: corner, borderWidth, shadowOffset per variant
      corner: (if $variant == "p3r" then 3 else 1 end),
      border: (if $variant == "p3r" then 2 else 3 end),
      shadowOffset: (if $variant == "p3r" then 5 else 7 end),
      walls: [
        ($cfg.background.greeterWall // ""),
        "@default@",
        ($cfg.background.lockWall // ""),
        ($cfg.background.wallpaperPath // "")
      ],
      thumbnail: ($cfg.background.thumbnailPath // "")
    }')

get() { jq -r "$1" <<<"$theme"; }

mkdir -p "$NB_OUT"

# ---------------------------------------------------------------- wallpaper
# The first of: the login screen wallpaper (settings), the NixOS option's,
# the lock screen's, the desktop's. Copied (a video: one frame of it), so the
# greeter never reads the home directory.
if [ "${NB_COPY_BACKGROUND:-0}" = 1 ]; then
  src=""
  while IFS= read -r wall; do
    [ "$wall" = "@default@" ] && wall="${NB_DEFAULT_BACKGROUND:-}"
    wall="${wall#file://}"
    if [ -n "$wall" ] && [ -f "$wall" ] && [ -r "$wall" ]; then
      src="$wall"
      break
    fi
  done < <(get '.walls[]')

  if [ -z "$src" ]; then
    rm -f "$NB_OUT/background" "$NB_OUT/background.src"
  else
    stamp="$src $(stat -c '%s %Y' -- "$src")"
    if [ "$(cat "$NB_OUT/background.src" 2>/dev/null)" != "$stamp" ]; then
      tmp="$NB_OUT/.background.tmp"
      rm -f "$tmp"
      case "${src,,}" in
      *.mp4 | *.webm | *.mkv | *.avi | *.mov | *.gif)
        ffmpeg -loglevel error -y -i "$src" -frames:v 1 -f image2 -c:v png "$tmp" ||
          rm -f "$tmp"
        ;;
      *) cp -- "$src" "$tmp" ;;
      esac
      if [ -s "$tmp" ]; then
        chmod 0644 "$tmp"
        mv -f "$tmp" "$NB_OUT/background"
        printf '%s\n' "$stamp" >"$NB_OUT/background.src"
      fi
    fi
  fi
fi

# ---------------------------------------------------------------------- CSS
c() { get ".colors.$1"; }
shapes=$(get .shapes)
corner=$(get .corner)
border=$(get .border)
offset=$(get .shadowOffset)
if [ "$shapes" = true ]; then
  radius="${corner}px"
  field_radius="${corner}px"
  button_radius="${corner}px"
  # Persona.outlineColor: the variant's edge colour (p5: Royal gold).
  card_border="${border}px solid @nb_edge"
  card_shadow="${offset}px ${offset}px 0 0 @nb_shadow"
  button_shadow="4px 4px 0 0 @nb_shadow"
  stripe="border-top: $((border * 2 + 2))px solid @nb_stripe;"
  title_style="font-style: italic; font-weight: 700; letter-spacing: 1px;"
else
  radius="23px"
  field_radius="9999px"
  button_radius="9999px"
  card_border="1px solid alpha(@nb_frame_border, 0.6)"
  # Tonal elevation, like the shell: the outline instead of a shadow.
  card_shadow="none"
  button_shadow="none"
  stripe=""
  title_style="font-weight: 600;"
fi
if [ "$(get .halftone)" = true ]; then
  # PersonaTexture: the art over the frame colour at 0.75 opacity.
  texture="background-image: linear-gradient(alpha(@nb_frame, 0.25), alpha(@nb_frame, 0.25)), url(\"file://$NB_TEXTURES/$(get .variant)-panel.png\");
  background-size: cover; background-position: center;"
else
  texture=""
fi
main_font=$(get .mainFont)
title_font=$(get .titleFont)

cat >"$NB_OUT/.regreet.css.tmp" <<EOF
/* Generated by nixbook-shell (scripts/greeter-theme.sh): the login screen in
   nixbook-shell's style$([ "$(get .persona)" = true ] && echo " (Persona $(get .variant))"). */
@define-color nb_bg $(c bg);
@define-color nb_surface1 $(c surface1);
@define-color nb_surface2 $(c surface2);
@define-color nb_surface3 $(c surface3);
@define-color nb_surface4 $(c surface4);
@define-color nb_on_surface $(c on_surface);
@define-color nb_on_surface_variant $(c on_surface_variant);
@define-color nb_outline $(c outline);
@define-color nb_outline_variant $(c outline_variant);
@define-color nb_primary $(c primary);
@define-color nb_on_primary $(c on_primary);
@define-color nb_primary_container $(c primary_container);
@define-color nb_on_primary_container $(c on_primary_container);
@define-color nb_secondary_container $(c secondary_container);
@define-color nb_on_secondary_container $(c on_secondary_container);
@define-color nb_error $(c error);
@define-color nb_error_container $(c error_container);
@define-color nb_on_error_container $(c on_error_container);
@define-color nb_frame $(c frame);
@define-color nb_frame_border $(c frame_border);
@define-color nb_shadow $(c shadow);
@define-color nb_stripe $(c stripe);
@define-color nb_edge $(c edge);

@define-color accent_color @nb_primary;
@define-color accent_bg_color @nb_primary;
@define-color accent_fg_color @nb_on_primary;
@define-color window_bg_color @nb_bg;
@define-color window_fg_color @nb_on_surface;
@define-color view_bg_color @nb_surface1;
@define-color view_fg_color @nb_on_surface;
@define-color popover_bg_color @nb_surface2;
@define-color popover_fg_color @nb_on_surface;
@define-color theme_selected_bg_color @nb_primary;
@define-color theme_selected_fg_color @nb_on_primary;

window, window.background {
  background-color: @nb_bg;
  color: @nb_on_surface;
  font-family: "$main_font", "Roboto", sans-serif;
}

/* Login card and clock: the shell's panels (PersonaFrame in the Persona
   style: bold border (Royal gold in p5), hard offset shadow, accent stripe, halftone art). */
overlay > frame.background {
  background-color: @nb_frame;
  $texture
  color: @nb_on_surface;
  border: $card_border;
  border-radius: $radius;
  box-shadow: $card_shadow;
  $stripe
}
overlay > frame.background:nth-child(2) {
  padding: 10px 14px;
}
/* The clock, hung from the top edge. */
overlay > frame.background:nth-child(3) {
  margin-top: 28px;
  padding: 8px 28px;
  border-radius: $radius;
  border-top-width: $([ "$shapes" = true ] && echo "$((border * 2 + 2))px" || echo "1px");
}
overlay > frame.background:nth-child(3) label {
  font-family: "$title_font", "$main_font", sans-serif;
  font-size: 30px;
  $title_style
  color: @nb_on_surface;
}

/* The form's own labels ("User:", "Session:", prompts), not the buttons'. */
frame.background grid > label {
  color: @nb_on_surface_variant;
}
frame.background grid > label:first-child {
  font-family: "$title_font", "$main_font", sans-serif;
  font-size: 22px;
  $title_style
  color: @nb_on_surface;
}

entry, passwordentry, combobox button.combo, dropdown > button {
  background: @nb_surface1;
  color: @nb_on_surface;
  border: 1px solid @nb_outline_variant;
  border-radius: $field_radius;
  box-shadow: none;
  outline: none;
  min-height: 40px;
  padding: 0 14px;
}
entry:focus-within, passwordentry:focus-within, combobox button.combo:focus {
  border-color: @nb_primary;
  box-shadow: inset 0 0 0 1px @nb_primary;
}
entry > text > selection, passwordentry > text > selection {
  background-color: @nb_secondary_container;
  color: @nb_on_secondary_container;
}

popover > contents, popover > arrow {
  background-color: @nb_surface2;
  color: @nb_on_surface;
  border: 1px solid @nb_outline_variant;
  border-radius: $radius;
}
popover modelbutton:hover, popover row:hover, popover row:selected {
  background-color: @nb_secondary_container;
  color: @nb_on_secondary_container;
}

button {
  background: @nb_surface3;
  color: @nb_on_surface;
  border: 1px solid @nb_outline_variant;
  border-radius: $button_radius;
  box-shadow: none;
  min-height: 40px;
  padding: 0 18px;
  font-weight: 600;
}
button:hover { background: @nb_surface4; }
button:checked {
  background: @nb_secondary_container;
  color: @nb_on_secondary_container;
}
button.suggested-action {
  background: @nb_primary;
  color: @nb_on_primary;
  border-color: @nb_primary;
  box-shadow: $button_shadow;
  font-family: "$title_font", "$main_font", sans-serif;
  $title_style
}
button.suggested-action:hover { background: mix(@nb_primary, white, 0.12); }
button.destructive-action {
  background: @nb_frame;
  color: @nb_on_surface;
  border: $card_border;
  box-shadow: $button_shadow;
}
button.destructive-action:hover {
  background: @nb_error_container;
  color: @nb_on_error_container;
}

/* Messages (e.g. "Touch your security key", fingerprint prompts, errors). */
infobar > revealer > box {
  background-color: @nb_primary_container;
  color: @nb_on_primary_container;
  border: $card_border;
  border-radius: $radius;
  box-shadow: $button_shadow;
}
infobar.error > revealer > box {
  background-color: @nb_error_container;
  color: @nb_on_error_container;
}
infobar label { color: inherit; font-weight: 600; }
EOF
chmod 0644 "$NB_OUT/.regreet.css.tmp"
mv -f "$NB_OUT/.regreet.css.tmp" "$NB_OUT/regreet.css"
