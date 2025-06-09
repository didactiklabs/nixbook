{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules;
  swaymsg = "${pkgs.swayfx}/bin/swaymsg";
in
{
  config = lib.mkIf cfg.swayConfig.enable {
    services.swayidle = {
      enable = lib.mkForce false;
    };
    wayland.windowManager.sway = {
      config.keybindings = lib.filterAttrsRecursive (name: value: value != null) { };
      extraConfig = ''
        exec ${swaymsg} create_output HEADLESS-1
        exec ${swaymsg} output HEADLESS-1 pos 0 0 res 2560x1440@120Hz scale 1
      '';
      extraSessionCommands = ''
        export WLR_BACKENDS="headless,libinput"
      '';
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
