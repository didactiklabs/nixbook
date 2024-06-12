{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules;
in {
  #home.file.".config/alacritty/alacritty.yml".source = ./alacritty.yml;
  programs.alacritty = {
    enable = true;

    settings = {
      import = ["~/.config/alacritty/custom.toml"];
      font = {
        #size = 10.0;
        normal.family = "Hack Nerd Font";
        normal.style = "Bold";
        bold.family = "Hack Nerd Font";
        bold.style = "Bold";
        italic.family = "Hack Nerd Font";
        italic.style = "Italic";
        bold_italic.family = "Hack Nerd Font";
        bold_italic.style = "Bold Italic";
      };
      window.padding.x = 2;
      window.padding.y = 2;
      window.opacity = 0.8;
      scrolling.history = 100000;
      scrolling.multiplier = 3;
      env = {"TERM" = "xterm-256color";};
      keyboard.bindings = [
        {
          key = "T";
          mods = "Control|Shift";
          action = "SpawnNewInstance";
        }
      ];
      selection.save_to_clipboard = true;
      colors = lib.mkIf (!cfg.pywalConfig.enable) {
        draw_bold_text_with_bright_colors = true;
        # Default colors
        primary.background = "0x280412";
        primary.foreground = "0xb7b8b9";
        # Normal colors
        normal = {
          black = "0x0c0d0e";
          red = "0xe31a1c";
          green = "0x22bb55";
          yellow = "0xddaa00";
          blue = "0x0066ff";
          magenta = "0x7566bb";
          cyan = "0x00bbff";
          white = "0xb7b8b9";
        };
        bright = {
          black = "0x737475";
          red = "0xe31a1c";
          green = "0x22bb55";
          yellow = "0xddaa00";
          blue = "0x0066ff";
          magenta = "0x7566bb";
          cyan = "0x00bbff";
          white = "0xfcfdfe";
        };
      };
    };
  };
}
