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
    # keep-place.py: a new window of these apps opens where the app's last
    # window was (workspace, column or floating position, size).
    systemd.user.services.niri-keep-place = {
      Unit = {
        Description = "Open windows of ${lib.concatStringsSep ", " (lib.attrNames cfg.niriConfig.keepPlace.apps)} where they were, in niri";
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
        Apps (by app id) whose new window opens where their last window was.
        niri opens every new window at the default width, beside whatever
        has focus, on the focused workspace; some apps replace their window
        with a new one: Moonlight hides its window while a game streams and
        opens a stream window, then the reverse when the game ends, and
        Vesktop shows a splash, then opens its main window, each start.

        The `niri-keep-place` user service follows niri's event stream: a
        new window of one of these apps (whose title matches `titles`, when
        set) goes to the place of the app's other open window, else of its
        last one, remembered across launches and reboots in
        `$XDG_STATE_HOME/niri-keep-place/places.json`: the same workspace
        (after a reboot, the same name, else the same index on the same
        monitor), floating or tiled like it, its size, and its column (when
        it has the focus: niri only moves the focused column) or floating
        position. `{ }` turns the service off.
      '';
    };
  };
}
