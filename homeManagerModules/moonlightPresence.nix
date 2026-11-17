{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules.moonlightPresence;
in
{
  options.customHomeManagerModules.moonlightPresence = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to show the game streamed with Moonlight as this desktop's
        Discord activity.

        Discord only detects local processes, so a game that runs on another
        machine and is watched through Moonlight shows nothing. With this, the
        `moonlight-presence` user service asks each of `hosts` over ssh, every
        15 s while Moonlight runs here, which Steam game it is running, looks
        the game up in Discord's public list of known games (by Steam id, then
        by name; kept a week in `~/.cache/moonlight-presence`) and announces
        it on Discord's local rich-presence socket (Vesktop: its arRPC
        setting must be on). The activity goes when the game or Moonlight
        closes.

        Needs key-based ssh from this user to the hosts. A game Steam doesn't
        run, or one Discord doesn't know, shows nothing.

        Used on: totoro (games on anya).
      '';
    };
    hosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "anya" ];
      description = ''
        ssh destinations of the machines games are streamed from, asked in
        this order: the first one running a game is shown.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.hosts != [ ];
        message = "customHomeManagerModules.moonlightPresence.hosts names no machine to ask.";
      }
    ];

    systemd.user.services.moonlight-presence = {
      Unit = {
        Description = "Show the game streamed with Moonlight as the Discord activity";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.python3}/bin/python3 ${./moonlightPresence/moonlight-presence.py} ${lib.escapeShellArgs cfg.hosts}";
        Environment = [ "PATH=${lib.makeBinPath [ pkgs.openssh ]}" ];
        Restart = "on-failure";
        RestartSec = 30;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
