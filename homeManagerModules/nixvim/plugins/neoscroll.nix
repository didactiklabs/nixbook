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
      plugins.neoscroll = {
        enable = true;
        settings = {
          # All these keys will be mapped to their corresponding default scrolling animation
          mappings = [
            "<C-u>"
            "<C-d>"
            "<C-b>"
            "<C-f>"
            "<C-y>"
            "<C-e>"
            "zt"
            "zz"
            "zb"
          ];
          hide_cursor = true;          # Hide cursor while scrolling
          stop_eof = true;             # Stop at <EOF> when scrolling downwards
          respect_scrolloff = false;   # Stop scrolling when the cursor reaches the scrolloff margin of the file
          cursor_scrolls_alone = true; # The cursor will keep on scrolling even if the window cannot scroll further
          easing_function = null;      # Default easing function
          pre_hook = null;             # Function to run before the scrolling animation starts
          post_hook = null;            # Function to run after the scrolling animation ends
          performance_mode = false;    # Disable "Performance Mode" on all buffers.
        };
      };
    };
  };
}