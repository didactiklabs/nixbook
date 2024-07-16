{ config, lib, ... }:
let cfg = config.customHomeManagerModules;
in {
  config = lib.mkIf cfg.hyprlandConfig.enable {
    wayland.windowManager.hyprland.settings = {
      monitor = lib.mkForce [
        ",preferred,auto,1"
        "eDP-1,preferred,0x587,1.0"
        "DP-8,1920x1080,1440x0,auto"
        "DP-9,1920x1080,3360x0,auto"
        "DP-10,1920x1080,1440x0,auto"
        "DP-11,1920x1080,3360x0,auto"
      ];
      windowrulev2 = [
        "workspace 1 silent,class:(vesktop)"
        "workspace 1 silent,title:(Spotify Premium)"
      ];
      exec-once =
        [ "[workspace 1 silent] spotify" "[workspace 1 silent] vesktop" ];
    };
  };
}
