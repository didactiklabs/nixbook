{
  config,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules;
in
{
  config = lib.mkIf cfg.nixvimConfig.enable {
    programs.nixvim = {
      plugins.smear-cursor = {
        enable = true;
        settings = {
          # Smear cursor color. Defaults to Cursor
          cursor_color = "#d3cdc3";

          # Background color. Defaults to Normal background
          normal_bg = "#282828";

          # Smear cursor when switching buffers
          smear_between_buffers = true;

          # Smear cursor when moving in insert mode
          smear_between_neighbor_lines = true;

          # Use floating windows to display smears outside buffers.
          # May have performance issues with Kitty terminal
          use_floating_windows = true;

          # Set to `true` if your font supports legacy computing symbols (block unicode symbols).
          # Smears will blend better on all backgrounds.
          legacy_computing_symbols_support = false;

          # Make the smear more exaggerated and stylish
          stiffness = 0.6; # Lower values make the smear more elastic/bouncy
          trailing_stiffness = 0.3; # Even lower for longer trailing effect
          distance_stop_animating = 0.5; # Continue animating for longer distances
          hide_target_hack = false; # Keep target visible for more dramatic effect
        };
      };
    };
  };
}
