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
    wayland.windowManager.sway.config.keybindings =
      lib.filterAttrsRecursive (name: value: value != null) {
      };
    wayland.windowManager.sway.extraConfig = ''
      exec ${swaymsg} create_output HEADLESS-1
      exec ${sunshine}
    '';
  };
}
