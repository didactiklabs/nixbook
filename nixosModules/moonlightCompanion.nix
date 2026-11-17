{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customNixOSModules.moonlightCompanion;
in
{
  options.customNixOSModules.moonlightCompanion = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether this machine tells the machines watching its games through
        Moonlight which Steam game runs (their Discord activity) and, with
        `musicRadioDir`, what the Cyberpunk 2077 mod Music Radio asks of its
        companion program (their game radio): the counterpart of
        `customHomeManagerModules.moonlightCompanion`.

        It opens no port and needs no login: Sunshine serves each app's cover
        picture to paired clients, so the `moonlight-companion` user service
        keeps `linkFile`, a copy of Sunshine's Desktop cover with a few text
        lines after the picture's end. The Sunshine app whose cover carries
        it must have `image-path = linkFile` (anya's Desktop app does).

        Used on: anya.
      '';
    };
    linkFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/user/1000/moonlight-companion/desktop.png";
      description = ''
        The cover picture the service keeps (Sunshine only serves `.png`
        names). On a tmpfs: it is rewritten up to 20 times a second while the
        game's radio plays.
      '';
    };
    musicRadioDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/data/Steam/steamapps/common/Cyberpunk 2077/bin/x64/plugins/cyber_engine_tweaks/mods/MusicRadio/data";
      description = ''
        The `data` folder of the Music Radio mod (Nexus 38098, its in-game
        files without its own companion program), or `null` for no game radio.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.moonlight-companion = {
      description = "What this machine's games tell the machines watching them through Moonlight";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      # The users the system itself runs (the greeter) have no games.
      unitConfig.ConditionUser = "!@system";
      serviceConfig = {
        ExecStart = lib.escapeShellArgs (
          [
            "${pkgs.python3}/bin/python3"
            "${./moonlightCompanion/moonlight-companion.py}"
            "--out"
            cfg.linkFile
            "--base"
            "${pkgs.sunshine}/assets/desktop.png"
          ]
          ++ lib.optionals (cfg.musicRadioDir != null) [
            "--radio"
            cfg.musicRadioDir
          ]
        );
        Restart = "on-failure";
        RestartSec = 30;
        Nice = 10;
      };
    };
  };
}
