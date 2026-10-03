{ pkgs, ... }:
let
  immichServer = "photos.didactiklabs.io";
  cyberPicturePath = "$HOME/.steam/steam/steamapps/compatdata/1091500/pfx/drive_c/users/steamuser/Pictures/Cyberpunk 2077";
  tw3PicturePath = "$HOME/.steam/steam/steamapps/compatdata/292030/pfx/drive_c/users/steamuser/Documents/The Witcher 3/screenshots";
  # Upload a screenshot folder to the Gaming album, then empty it. A script
  # rather than an inline `bash -c '…'`: the old one-liner quoted the glob
  # (`rm -fr "…/*"`), so the folder was never emptied.
  mkUpload =
    name: picturePath:
    pkgs.writeShellScript "immich-${name}" ''
      set -euo pipefail
      dir="${picturePath}"
      ${pkgs.immich-go}/bin/immich-go upload from-folder --no-ui \
        --api-key "$(${pkgs.coreutils}/bin/cat "$HOME/.immich-token")" \
        --server https://${immichServer} --into-album Gaming "$dir/"
      ${pkgs.coreutils}/bin/rm -fr -- "$dir"/*
    '';
in
{
  systemd.user = {
    services = {
      immich-tw3 = {
        description = "Run my command";
        serviceConfig = {
          ExecStart = mkUpload "tw3" tw3PicturePath;
        };
      };
      immich-cyberpunk = {
        description = "Run my command";
        serviceConfig = {
          ExecStart = mkUpload "cyberpunk" cyberPicturePath;
        };
      };
    };
    # OnUnitActiveSec alone never fires (it counts from the service's last
    # activation, and nothing starts the service otherwise): OnStartupSec
    # gives the first run, 5 min after the user manager starts.
    timers = {
      immich-tw3-timer = {
        enable = true;
        description = "Timer to run myService every 5 minutes for tw3";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnStartupSec = "5min";
          OnUnitActiveSec = "5min";
          Unit = "immich-tw3.service";
        };
      };
      immich-cyberpunk-timer = {
        enable = true;
        description = "Timer to run myService every 5 minutes for CP2077";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnStartupSec = "5min";
          OnUnitActiveSec = "5min";
          Unit = "immich-cyberpunk.service";
        };
      };
    };
  };
}
