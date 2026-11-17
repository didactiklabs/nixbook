{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules.moonlightCompanion;
  shell = config.programs.nixbook-shell or { };
in
{
  options.customHomeManagerModules.moonlightCompanion = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to follow the games watched here through Moonlight: the
        `moonlight-companion` user service reads what the streaming machine
        says (`customNixOSModules.moonlightCompanion` there) and acts on it
        here.

        The link is Sunshine's own: while Moonlight runs and a paired host is
        streaming, the service fetches that host's Desktop cover picture on
        Sunshine's port, with Moonlight's own pairing (read from Moonlight's
        settings file, the host checked against the certificate kept at the
        pairing), and reads the text lines after the picture's end. No ssh,
        no other port, nothing to configure: hosts are the ones paired in
        Moonlight.

        Used on: totoro (games on anya).
      '';
    };
    discordActivity = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Show the Steam game the host runs as this desktop's Discord activity
        (Discord only detects local processes). The game is found in
        Discord's public list of known games (by Steam id, then by name; kept
        a week in `~/.cache/moonlight-companion`) and announced on Discord's
        local rich-presence socket (Vesktop: its arRPC setting must be on). A
        game Steam doesn't run, or one Discord doesn't know, shows nothing.
      '';
    };
    gameRadio = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Be the companion program of the Cyberpunk 2077 mod Music Radio
        (Nexus 38098) for the game on the host: while its "Music" station is
        on, the YouTube Music panel's own player (nixbook-shell's
        nixbook-ytmusic) gets the acoustics the game asks for (in the car,
        beside it, tunnels, clubs...), as a filter chain changed in place, and
        the station's play / pause / next / previous run on it. The music is
        played here and mixed with the stream's sound; the game's now-playing
        card stays empty (the link goes one way). Needs nixbook-shell.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.gameRadio || (shell.enable or false);
        message = "customHomeManagerModules.moonlightCompanion.gameRadio plays through nixbook-shell's YouTube Music player: enable nixbookShellConfig.";
      }
    ];

    systemd.user.services.moonlight-companion = {
      Unit = {
        Description = "Discord activity and game radio for the games watched through Moonlight";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = lib.escapeShellArgs (
          [
            "${pkgs.python3}/bin/python3"
            "${./moonlightCompanion/moonlight-companion-client.py}"
          ]
          ++ lib.optional cfg.discordActivity "--discord"
          ++ lib.optionals cfg.gameRadio [
            "--radio"
            "--ytmusic"
            "${shell.package.ytmusic}/bin/nixbook-ytmusic"
          ]
        );
        Restart = "on-failure";
        RestartSec = 30;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
