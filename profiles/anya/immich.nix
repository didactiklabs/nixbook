{ pkgs, ... }:
let
  immichServer = "photos.didactiklabs.io";
  cyberPicturePath = "$HOME/.steam/steam/steamapps/compatdata/1091500/pfx/drive_c/users/steamuser/Pictures/Cyberpunk 2077";
  tw3PicturePath = "$HOME/.steam/steam/steamapps/compatdata/292030/pfx/drive_c/users/steamuser/Documents/The Witcher 3/screenshots";
in
{
  systemd.user = {
    services = {
      immich-tw3 = {
        description = "Run my command";
        serviceConfig = {
          ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.immich-go}/bin/immich-go upload from-folder --no-ui --api-key $(${pkgs.coreutils}/bin/cat $HOME/.immich-token) --server https://${immichServer} --into-album Gaming \"${tw3PicturePath}/\" && ${pkgs.coreutils}/bin/rm -fr \"${tw3PicturePath}/*\"'";
        };
      };
      immich-cyberpunk = {
        description = "Run my command";
        serviceConfig = {
          ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.immich-go}/bin/immich-go upload from-folder --no-ui --api-key $(${pkgs.coreutils}/bin/cat $HOME/.immich-token) --server https://${immichServer} --into-album Gaming \"${cyberPicturePath}/\" && ${pkgs.coreutils}/bin/rm -fr \"${cyberPicturePath}/*\"'";
        };
      };
    };
    timers = {
      immich-tw3-timer = {
        enable = true;
        description = "Timer to run myService every 5 minutes for tw3";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnUnitActiveSec = "5min";
          Persistent = true;
          Unit = "immich-tw3.service";
        };
      };
      immich-cyberpunk-timer = {
        enable = true;
        description = "Timer to run myService every 5 minutes for CP2077";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnUnitActiveSec = "5min";
          Persistent = true;
          Unit = "immich-cyberpunk.service";
        };
      };
    };
  };
}
