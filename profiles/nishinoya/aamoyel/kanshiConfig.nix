{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules;
in {
  config = {
    ## we will need to override it someday or make a new pr in nixpkgs
    ## https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/tools/graphics/wdisplays/default.nix#L19
    ## https://github.com/luispabon/wdisplays
    ## the new repository is here https://github.com/artizirk/wdisplays
    wayland.windowManager.sway.config.startup = lib.mkIf cfg.swayConfig.enable [
      {
        command = "${pkgs.systemd}/bin/systemctl --user restart kanshi";
        always = true;
      }
    ];
    home.packages = [
      pkgs.kanshi
    ];
    services.kanshi = {
      enable = true;
      systemdTarget = "";
      settings = [
        {
          profile = {
            name = "undocked";
            outputs = [
              {
                criteria = "eDP-1";
                position = "0,0";
                mode = "2880x1800@60.002Hz";
                scale = 1.7;
              }
            ];
          };
        }
        {
          profile = {
            name = "home-docked";
            outputs = [
              {
                criteria = "eDP-1";
                position = "254,431";
                mode = "2880x1800@60.002Hz";
                scale = 2.0;
              }
              {
                criteria = "DP-8";
                position = "1694,0";
                mode = "1920x1080@60.002Hz";
                scale = 1.0;
              }
              {
                criteria = "DP-9";
                position = "3614,0";
                mode = "1920x1080@60.002Hz";
                scale = 1.0;
              }
            ];
            exec = [
              "${pkgs.swayfx}/bin/swaymsg workspace 1, move workspace to eDP-1"
              "${pkgs.swayfx}/bin/swaymsg workspace 2, move workspace to DP-8"
              "${pkgs.swayfx}/bin/swaymsg workspace 3, move workspace to DP-9"
            ];
          };
        }
      ];
    };
  };
}
