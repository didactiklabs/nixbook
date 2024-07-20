{ config, pkgs, lib, ... }:
let cfg = config.customHomeManagerModules;
in {
  config = {
    ## we will need to override it someday or make a new pr in nixpkgs
    ## https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/tools/graphics/wdisplays/default.nix#L19
    ## https://github.com/luispabon/wdisplays
    ## the new repository is here https://github.com/artizirk/wdisplays
    wayland.windowManager.sway.config.startup =
      lib.mkIf cfg.swayConfig.enable [{
        command = "${pkgs.systemd}/bin/systemctl --user restart kanshi";
        always = true;
      }];
    home.packages = [ pkgs.kanshi ];
    services.kanshi = {
      enable = true;
      systemdTarget = "";
      settings = [
        {
          profile = {
            name = "undocked";
            outputs = [{
              criteria = "eDP-1";
              position = "0,0";
              mode = "1920x1080@60.002Hz";
              scale = 1.0;
            }];
          };
        }
        {
          profile = {
            name = "home-docked";
            outputs = [
              {
                criteria = "eDP-1";
                position = "3000,0";
                mode = "1920x1080@60.033Hz";
                scale = 1.0;
              }
              {
                criteria = "DP-6";
                position = "1080,0";
                mode = "1920x1080@60.000Hz";
                scale = 1.0;
              }
              {
                criteria = "DP-5";
                position = "0,0";
                mode = "1920x1080@60.000Hz";
                scale = 1.0;
                transform = "90";
              }
            ];
            exec = [
              "${pkgs.swayfx}/bin/swaymsg workspace 1, move workspace to DP-6"
              "${pkgs.swayfx}/bin/swaymsg workspace 2, move workspace to DP-6"
              "${pkgs.swayfx}/bin/swaymsg workspace 3, move workspace to DP-6"
              "${pkgs.swayfx}/bin/swaymsg workspace 4, move workspace to DP-6"
              "${pkgs.swayfx}/bin/swaymsg workspace 5, move workspace to DP-5"
              "${pkgs.swayfx}/bin/swaymsg workspace 6, move workspace to eDP-1"
            ];
          };
        }
      ];
    };
  };
}
