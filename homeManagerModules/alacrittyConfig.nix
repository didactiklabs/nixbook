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
        size = lib.mkForce 10.0;
        normal.family = lib.mkForce "Hack Nerd Font";
        normal.style = lib.mkForce "Bold";
        bold.family = "Hack Nerd Font";
        bold.style = "Bold";
        italic.family = "Hack Nerd Font";
        italic.style = "Italic";
        bold_italic.family = "Hack Nerd Font";
        bold_italic.style = "Bold Italic";
      };
      window.padding.x = 2;
      window.padding.y = 2;
      window.opacity = lib.mkIf (!cfg.stylixConfig.enable) 0.8;
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
      colors = lib.mkIf (!cfg.stylixConfig.enable) {
        draw_bold_text_with_bright_colors = true;
        # Default colors
        primary.background = "#0A0E14";
        primary.foreground = "#B3B1AD";
        # Normal colors
        normal = {
          black = "#01060E";
          red = "#EA6C73";
          green = "#91B362";
          yellow = "#F9AF4F";
          blue = "#53BDFA";
          magenta = "#FAE994";
          cyan = "#90E1C6";
          white = "#C7C7C7";
        };
        bright = {
          black = "#686868";
          red = "#F07178";
          green = "#C2D94C";
          yellow = "#FFB454";
          blue = "#59C2FF";
          magenta = "#FFEE99";
          cyan = "#95E6CB";
          white = "#FFFFFF";
        };
      };
    };
  };
}
