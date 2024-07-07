{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules;
in {
  options.customHomeManagerModules.desktopApps = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable desktopApps globally or not
      '';
    };
  };
  config = lib.mkIf cfg.desktopApps.enable {
    home.packages = with pkgs; [
      # apps
      wdisplays # display manager
      vesktop # discord
      firefox
      thunderbird
    ];
  };
}
