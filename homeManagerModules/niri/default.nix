{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.customHomeManagerModules;
  keepPlaceConfig = pkgs.writeText "niri-keep-place.json" (
    builtins.toJSON { inherit (cfg.niriConfig.keepPlace) apps; }
  );
in
{
  imports = [
    ./niriConfig.nix
  ];
  config = lib.mkIf (cfg.niriConfig.enable && cfg.niriConfig.keepPlace.apps != { }) {
    # keep-place.py: a window these apps reopen gets the place of the one it
    # replaces (workspace, column or floating position, size).
    systemd.user.services.niri-keep-place = {
      Unit = {
        Description = "Give reopened windows (${lib.concatStringsSep ", " (lib.attrNames cfg.niriConfig.keepPlace.apps)}) their place back in niri";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
        # niri imports NIRI_SOCKET into the user manager when it starts.
        ConditionEnvironment = "NIRI_SOCKET";
        X-Restart-Triggers = [ keepPlaceConfig ];
      };
      Service = {
        ExecStart = lib.escapeShellArgs [
          "${pkgs.python3}/bin/python3"
          "-I"
          "${./keep-place.py}"
          "${keepPlaceConfig}"
        ];
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
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.titles = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = ''
              Regular expressions (Python `re.search`) a window's title must
              match to count: the app's main window, not its splash or
              popouts. Empty: every window of the app.
            '';
          };
        }
      );
      default = {
        "com.moonlight_stream.Moonlight" = { };
        # Vesktop's main window: "Discord", "(7) Discord | #channel | server",
        # "• Discord | @someone"; not its splash ("vesktop") nor popouts
        # ("Discord Popout").
        vesktop.titles = [ "Discord( \\||$)" ];
      };
      description = ''
        Apps (by app id) whose window niri should give its place back when
        the app closes it and opens a new one. niri opens every new window
        at the default width, beside whatever has focus, on the focused
        workspace: Moonlight hides its window while a game streams and opens
        a stream window, then the reverse when the game ends, and Vesktop
        restarts itself (updates, the Electron bridge) through a splash.

        The `niri-keep-place` user service follows niri's event stream: a
        new window of one of these apps (whose title matches `titles`, when
        set) opening while another of the app is open, or closed less than
        30 s ago, goes to that window's workspace, floating or tiled like
        it, its size, and its column (when it has the focus: niri only moves
        the focused column) or floating position. Nothing is kept longer:
        an app launched later opens like any other window. `{ }` turns the
        service off.
      '';
    };
  };
}
