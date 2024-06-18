{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules;
  swaymsg = "${pkgs.sway}/bin/swaymsg";
  sunshine = "${pkgs.sunshine}/bin/sunshine";
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
      exec ${sunshine}
    '';
    wayland.windowManager.sway.extraSessionCommands = ''
      export WLR_BACKENDS="headless,libinput"
    '';
  };
}
