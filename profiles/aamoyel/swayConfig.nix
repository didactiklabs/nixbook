{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules.sway;
in {
  config = lib.mkIf cfg.enable {
    wayland.windowManager.sway.config.keybindings = lib.filterAttrsRecursive (name: value: value != null) {
      "Mod4+q" = "exec ${pkgs.copyq}/bin/copyq toggle";
    };
  };
}
