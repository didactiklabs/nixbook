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
    wayland.windowManager.sway.config.keybindings =
      lib.filterAttrsRecursive (name: value: value != null) {
      };
    wayland.windowManager.sway.config.extraConfig = ''
      ${swaymsg} create_output HEADLESS-1
    '';
  };
}
