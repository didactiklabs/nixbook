{ config, pkgs, lib, ... }:
let
  cfg = config.customHomeManagerModules;
  swaymsg = "${pkgs.sway}/bin/swaymsg";
in {
  config = lib.mkIf cfg.swayConfig.enable {
    services.swayidle = { enable = lib.mkForce false; };
    wayland.windowManager.sway = {
      config.keybindings =
        lib.filterAttrsRecursive (name: value: value != null) { };
      extraConfig = ''
        exec ${swaymsg} create_output HEADLESS-1
        exec ${swaymsg} output HEADLESS-1 pos 0 0 res 3840x2160@120Hz scale 2
      '';
      extraSessionCommands = ''
        export WLR_BACKENDS="headless,libinput"
      '';
      sway.config.window.commands = [
        {
          command = "opacity 1.0";
          criteria = { class = ".*"; };
        }
        {
          command = "opacity 0.8";
          criteria = { app_id = "Alacritty"; };
        }
      ];
    };
  };
}
