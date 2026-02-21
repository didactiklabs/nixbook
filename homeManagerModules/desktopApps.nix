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
      vesktop = {
        enable = true;
        settings = {
          discordBranch = "stable";
          splashColor = "rgb(220, 220, 223)";
          splashBackground = "rgb(0, 0, 0)";
          splashTheming = true;
          minimizeToTray = false;
          checkUpdates = false;
          arRPC = true;
          spellCheckLanguages = [
            "en-US"
            "fr-FR"
            "c"
          ];
          hardwareVideoAcceleration = true;
        };
      };
    };
    home.packages = with pkgs; [
      # apps
      spotify
      signal-desktop
      obs-studio
      localsend # send files with other devices (android etc..) on LAN
      wdisplays # display manager
      firefox
      pinta # paint
    ];
  };
}
