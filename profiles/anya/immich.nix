{ pkgs, ... }:
let
  immichServer = "photos.didactiklabs.io";
  cyberPicturePath = "$HOME/.steam/steam/steamapps/compatdata/1091500/pfx/drive_c/users/steamuser/Pictures/Cyberpunk 2077";
  tw3PicturePath = "$HOME/.steam/steam/steamapps/compatdata/292030/pfx/drive_c/users/steamuser/Documents/The Witcher 3/screenshots";
  # Upload a screenshot folder to the Gaming album, then empty it. A script
  # rather than an inline `bash -c '…'`: the old one-liner quoted the glob
  # (`rm -fr "…/*"`), so the folder was never emptied.
  # The screenshots are moved aside first and only those are uploaded then
  # deleted: one taken during the upload stays for the next run (emptying the
  # folder after the upload deleted it unsent). A failed upload leaves them
  # in .immich-upload, sent with the next run. The API key goes through a
  # private config file, not the command line other users can read in ps.
  mkUpload =
    name: picturePath:
    pkgs.writeShellScript "immich-${name}" ''
      set -euo pipefail
      dir="${picturePath}"
      [ -d "$dir" ] || exit 0
      stage="$dir/.immich-upload"
      ${pkgs.coreutils}/bin/mkdir -p "$stage"
      shopt -s nullglob
      for f in "$dir"/*; do
        ${pkgs.coreutils}/bin/mv -- "$f" "$stage/"
      done
      files=("$stage"/*)
      [ "''${#files[@]}" -gt 0 ] || exit 0
      config=$(umask 077 && ${pkgs.coreutils}/bin/mktemp --suffix=.yaml)
      trap '${pkgs.coreutils}/bin/rm -f "$config"' EXIT
      printf 'upload:\n  api-key: "%s"\n' "$(${pkgs.coreutils}/bin/cat "$HOME/.immich-token")" >"$config"
      ${pkgs.immich-go}/bin/immich-go --config "$config" upload from-folder --no-ui \
        --server https://${immichServer} --into-album Gaming "$stage/"
      ${pkgs.coreutils}/bin/rm -fr -- "$stage"
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
