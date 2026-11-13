{
  config,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules;
in
{
  config = lib.mkIf cfg.swayConfig.enable {
    services.swayidle = {
      enable = lib.mkForce false;
    };
    wayland.windowManager.sway = {
      config.keybindings = lib.filterAttrsRecursive (name: value: value != null) { };
      # The headless backend (started by greetd, profiles/anya/default.nix)
      # creates HEADLESS-1; it has no mode list, so sway sets this as a
      # custom mode. This is the resolution Moonlight streams.
      config.output."HEADLESS-1" = {
        mode = "2560x1440@60Hz";
        pos = "0 0";
        scale = "1";
      };
      config.window.commands = lib.mkForce [
        {
          command = "opacity 1.0, shadows enable, blur enable, blur_passes 5, blur_radius 6, corner_radius 10";
          criteria = {
            class = ".*";
          };
        }
        {
          command = "floating enable, sticky enable, resize set height 600px width 550px, move position cursor, move down 330";
          criteria = {
            app_id = "copyq";
          };
        }
        {
          command = "opacity 1.0";
          criteria = {
            app_id = "com.moonlight_stream.Moonlight";
          };
        }

        {
          command = "opacity 0.8";
          criteria = {
            app_id = "Kitty";
          };
        }
      ];
    };
  };
}
