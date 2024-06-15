{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules;
in {
  config = lib.mkIf cfg.sway.enable {
    wayland.windowManager.sway.config.startup = [
      {
        command = "${pkgs.jellyfin-mpv-shim}/bin/jellyfin-mpv-shim";
        always = false;
      }
      {
        command = "${pkgs.nextcloud-client}/bin/nextcloud";
        always = false;
      }
    ];
    wayland.windowManager.sway.config.keybindings =
      lib.filterAttrsRecursive (name: value: value != null) {
      };
  };
}
