{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules;
in {
  config = lib.mkIf cfg.swayConfig.enable {
    systemd.user.services.jellyfin-mpv-shim = {
      Unit = {
        Description = "Jellyfin mpv";
      };
      Install = {
        WantedBy = ["graphical-session.target"];
      };
      Unit = {
        After = ["graphical-session.target"];
      };
      Service = {
        ExecStartPre = "${pkgs.coreutils}/sleep 30";
        ExecStart = "${pkgs.jellyfin-mpv-shim}/bin/jellyfin-mpv-shim";
        Restart = "always";
      };
    };
    systemd.user.services.nextcloud-client = {
      Unit = {
        Description = "Nextcloud";
      };
      Install = {
        WantedBy = ["graphical-session.target"];
      };
      Unit = {
        After = ["graphical-session.target"];
      };
      Service = {
        ExecStartPre = "${pkgs.coreutils}/sleep 30";
        ExecStart = "${pkgs.nextcloud-client}/bin/nextcloud";
        Restart = "always";
      };
    };
  };
}
