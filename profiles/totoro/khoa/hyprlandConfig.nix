{
  config,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules;
in
{
  config = lib.mkIf cfg.hyprlandConfig.enable {
    wayland.windowManager.hyprland.settings = {
      monitor = lib.mkForce [
        ",preferred,auto,1"
        "eDP-1,preferred,0x755,1.6"
        "DP-8,1920x1080,1800x230,auto"
        "DP-9,2560x1440,3720x0,auto"
        "DP-10,1920x1080,1800x0,auto"
        "DP-11,1920x1080,3720x0,auto"
      ];
      windowrulev2 = [
        "workspace 1 silent,fullscreen 1,class:(thunderbird)"
        "workspace 1 silent,fullscreen 1,class:(vesktop)"
        "workspace 1 silent,fullscreen 1,title:(Spotify Premium)"
        "workspace 1 silent,fullscreen 1,class:(signal)"
        "workspace 3 silent,fullscreen 1,class:(com.moonlight_stream.Moonlight)"
        "workspace 3 silent,fullscreen 1,class:(mpv)"
      ];
      exec-once = [
        # "[workspace 1 silent] spotify"
        # "[workspace 1 silent] vesktop"
        # "[workspace 1 silent] thunderbird"
        # "[workspace 1 silent] signal-desktop"
      ];
    };
  };
}
