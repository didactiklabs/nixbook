{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules;
in {
  config = lib.mkIf cfg.sway.enable {
    ## we will need to override it someday or make a new pr in nixpkgs
    ## https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/tools/graphics/wdisplays/default.nix#L19
    ## https://github.com/luispabon/wdisplays
    ## the new repository is here https://github.com/artizirk/wdisplays
    wayland.windowManager.sway.config.startup = [
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
          profile.name = "undocked";
          profile.outputs = [
            {
              criteria = "eDP-1";
              position = "0,0";
              mode = "2880x1800@60.002Hz";
              scale = 1.7;
            }
          ];
        }
        {
          profile.name = "home-docked";
          profile.outputs = [
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
        }
      ];
    };
  };
}
