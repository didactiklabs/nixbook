{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules;
  swaymsg = "${pkgs.sway}/bin/swaymsg";
in {
  config = lib.mkIf cfg.sway.enable {
    services.swayidle = {
      enable = lib.mkForce false;
    };
    wayland.windowManager.sway.config.keybindings =
      lib.filterAttrsRecursive (name: value: value != null) {
      };
    wayland.windowManager.sway.extraConfig = ''
      exec ${swaymsg} create_output HEADLESS-1
      exec output HEADLESS-1 mode 3840x2160 position 5000,2000
    '';
    wayland.windowManager.sway.extraSessionCommands = ''
      export WLR_BACKENDS="headless,libinput"
    '';
    wayland.windowManager.sway.config.window.commands = [
      {
        command = "opacity 1.0";
        criteria = {
          class = ".*";
        };
      }
    ];
  };
}
