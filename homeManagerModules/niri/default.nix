{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.customHomeManagerModules;
in
{
  imports = [
    ./niriConfig.nix
  ];
  config = lib.mkIf (cfg.niriConfig.enable && cfg.niriConfig.keepPlace.apps != [ ]) {
    # keep-place.py: a reopened window of these apps gets the place of the
    # one it replaces (workspace, column or floating position, size).
    systemd.user.services.niri-keep-place = {
      Unit = {
        Description = "Give reopened windows (${lib.concatStringsSep ", " cfg.niriConfig.keepPlace.apps}) their place back in niri";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
        # niri imports NIRI_SOCKET into the user manager when it starts.
        ConditionEnvironment = "NIRI_SOCKET";
      };
      Service = {
        ExecStart = lib.escapeShellArgs (
          [
            "${pkgs.python3}/bin/python3"
            "-I"
            "${./keep-place.py}"
          ]
          ++ cfg.niriConfig.keepPlace.apps
        );
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
  options.customHomeManagerModules.niriConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable per-user Niri compositor configuration.

        Manages the full Niri scrollable-tiling user environment via Home Manager:
          - niriConfig.nix: programs.niri.settings — keybindings, window rules,
            output/monitor configuration (via kanshi-style prefer-output rules),
            input device settings, animations, environment variables,
            spawn-at-startup commands, and workspace configuration

        Niri arranges windows in an infinite horizontal scrollable strip.
        Key concepts: columns (vertical stacks), workspaces (virtual desktops),
        and outputs (physical monitors).

        Requires the system-level nixosModules/niri.nix to be enabled
        (customNixOSModules.niri.enable = true).

        Used on: totoro (primary), nishinoya (primary).
      '';
    };
    keepPlace.apps = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "com.moonlight_stream.Moonlight" ];
      description = ''
        App ids whose windows niri should give their place back when the app
        replaces its window with a new one. Moonlight hides its window while
        a game streams and opens a stream window, then the reverse when the
        game ends; niri saw a new window each time and opened it at the
        default width, beside whatever had focus, on the focused workspace.

        The `niri-keep-place` user service follows niri's event stream: a
        window of one of these apps opening while another of the same app
        is open, or closed less than a minute ago, is moved to that window's
        workspace, made floating or tiled like it, given its size and put
        at its column (when it has the focus) or its floating position. An
        app launched afresh opens like any other window. `[ ]` turns the
        service off.
      '';
    };
  };
}
