{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules;
in
{
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
    programs = {
      zathura.enable = true;
      imv.enable = true;
    };
    home.packages = with pkgs; [
      # apps
      signal-desktop
      obs-studio
      localsend # send files with other devices (android etc..) on LAN
      wdisplays # display manager
      vesktop # discord
      firefox
      pinta # paint
    ];
  };
}
