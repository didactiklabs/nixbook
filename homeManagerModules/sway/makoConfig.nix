{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules;
in {
  config = lib.mkIf cfg.sway.enable {
    home.packages = [
      pkgs.libnotify
      pkgs.numix-icon-theme-square
    ];

    services.mako = {
      enable = true;
      actions = true;
      layer = "top";
      anchor = "top-right";
      font = "Hack Nerd Font 9";
      backgroundColor = "#1E2029";
      textColor = "#bbc2cf";
      width = 300;
      height = 100;
      margin = "10";
      padding = "14";
      borderSize = 1;
      borderColor = "#1a1c25";
      borderRadius = 10;
      icons = true;
      maxIconSize = 32;
      #iconPath = "";
      markup = true;
      format = "<b>%s</b>\\n%b";
      defaultTimeout = 5000;
      extraConfig = ''
        [urgency=low]
        border-color=#1E2029

        [urgency=normal]
        border-color=#1E2029

        [urgency=high]
        border-color=#cc6666
        default-timeout=0
      '';
    };
  };
}
