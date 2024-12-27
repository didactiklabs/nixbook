{ config, lib, ... }:
let
  cfg = config.customHomeManagerModules;
in
{
  config = lib.mkIf cfg.hyprlandConfig.enable {
    wayland.windowManager.hyprland.settings = {
      monitor = lib.mkForce [
        ",preferred,auto,1"
        "eDP-1,preferred,3000x0,1.666667"
        "DP-10,1920x1080,1080x0,1.0"
        "DP-9,1920x1080,0x0,1.0, transform, 1"
      ];
      windowrulev2 = [
        "workspace 1 silent,class:(vesktop)"
        "workspace 1 silent,title:(Spotify Premium)"
      ];
      exec-once = [
        "[workspace 1 silent] spotify"
        "[workspace 1 silent] vesktop"
      ];
    };
  };
}
