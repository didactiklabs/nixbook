# Persona-style window open/close: a jagged diagonal slash sweeps across the
# window, trailing an accent band with a thin ink edge (Persona 5's red/white
# "all-out attack" cut), revealing the window on open and cutting it away on
# close. Cheap: one texture read per pixel, no loops.
#
# `accent` and `ink` are "#rrggbb" colours (nixbook-shell's Persona palette,
# or the stylix accent/foreground for other themes).
{
  lib,
  accent,
  ink,
}:
let
  channel = hex: i: toString ((lib.fromHexString (builtins.substring (1 + 2 * i) 2 hex)) / 255.0);
  vec3 = hex: "vec3(${channel hex 0}, ${channel hex 1}, ${channel hex 2})";

  # Shared by both shaders. `behind` is what is left once the slash has
  # passed (the window on open, nothing on close); `ahead` is what it has not
  # reached yet. Everything is in logical pixels so the angle, band widths
  # and teeth look the same on any window size.
  slash = ''
    vec4 persona_slash(vec3 coords_geo, vec3 size_geo, float progress, bool opening) {
        vec2 px = coords_geo.xy * size_geo.xy;

        // Rounded-corner mask matching the window rule's 12px radius.
        vec2 half_size = size_geo.xy * 0.5;
        vec2 q = abs(px - half_size) - half_size + 12.0;
        float corner = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - 12.0;
        float inside = clamp(0.5 - corner, 0.0, 1.0);
        if (inside <= 0.0) {
            return vec4(0.0);
        }

        // Diagonal distance along the cut (leaning ~20 degrees), with
        // sawtooth teeth on the edge.
        float slant = 0.36;
        float teeth = abs(fract(px.y / 36.0) - 0.5) * 16.0;
        float d = px.x + (size_geo.y - px.y) * slant + teeth;

        float accent_w = 18.0;
        float ink_w = 4.0;
        float band = accent_w + ink_w;
        float total = size_geo.x + size_geo.y * slant + 8.0;
        float edge = progress * (total + band) - band;

        // 1px anti-aliased steps: passed the accent start, the ink start,
        // and the leading edge.
        float past_accent = clamp(d - edge + 0.5, 0.0, 1.0);
        float past_ink = clamp(d - (edge + accent_w) + 0.5, 0.0, 1.0);
        float past_lead = clamp(d - (edge + band) + 0.5, 0.0, 1.0);

        vec3 tex = niri_geo_to_tex * coords_geo;
        vec4 win = texture2D(niri_tex, tex.st);
        vec4 behind = opening ? win : vec4(0.0);
        vec4 ahead = opening ? vec4(0.0) : win;

        vec4 color = mix(behind, vec4(${vec3 accent}, 1.0), past_accent);
        color = mix(color, vec4(${vec3 ink}, 1.0), past_ink);
        color = mix(color, ahead, past_lead);
        return color * inside;
    }
  '';
in
{
  animations = {
    workspace-switch = {
      kind.easing = {
        duration-ms = 300;
        curve = "ease-out-cubic";
      };
    };

    window-open = {
      kind.easing = {
        duration-ms = 260;
        curve = "ease-out-expo";
      };
      custom-shader = ''
        ${slash}
        vec4 open_color(vec3 coords_geo, vec3 size_geo) {
            return persona_slash(coords_geo, size_geo, niri_clamped_progress, true);
        }
      '';
    };

    window-close = {
      kind.easing = {
        duration-ms = 200;
        curve = "ease-out-cubic";
      };
      custom-shader = ''
        ${slash}
        vec4 close_color(vec3 coords_geo, vec3 size_geo) {
            return persona_slash(coords_geo, size_geo, niri_clamped_progress, false);
        }
      '';
    };
  };
}
