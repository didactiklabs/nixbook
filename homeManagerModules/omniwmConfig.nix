# OmniWM (macOS 26+, Apple Silicon): a tiling window manager with niri-style
# scrolling columns, the macOS machines' stand-in for niri. Home Manager's
# programs.omniwm installs it and runs it as a launchd agent.
#
# Settings: OmniWM 0.8 rejects a settings.toml missing any required key, so
# the file stays OmniWM's own (written at its first start, editable in its
# Settings window), and the keys and hotkeys set here are merged into it
# (omniwm/apply-settings.py) at each switch and whenever the file changes: a
# key set in Nix is put back if changed in the Settings window, every other
# key is OmniWM's to keep. Hotkeys are niri's binds (KEYBINDS.md) with Option
# as niri's Mod (OmniWM's own default modifier; Command stays the apps').
#
# OmniWM asks for Accessibility and Input Monitoring at its first start: that
# can only be granted in System Settings > Privacy & Security, once.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.customHomeManagerModules.omniwmConfig;
  settingsFile = "${config.xdg.configHome}/omniwm/settings.toml";
  pinned = pkgs.writeText "omniwm-nix-settings.json" (
    builtins.toJSON {
      inherit (cfg) settings hotkeys;
    }
  );
  python = pkgs.python3.withPackages (ps: [ ps.tomli-w ]);
  apply = pkgs.writeShellScript "omniwm-apply-nix-settings" ''
    exec ${python}/bin/python3 ${./omniwm/apply-settings.py} ${pinned} ${lib.escapeShellArg settingsFile}
  '';
  # Each leaf a mkDefault: a profile sets one key without dropping the rest.
  defaults = lib.mapAttrsRecursive (_: lib.mkDefault);
in
{
  options.customHomeManagerModules.omniwmConfig = {
    enable = lib.mkEnableOption "OmniWM, the tiling window manager of the macOS machines";
    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      example = {
        gaps.size = 8.0;
      };
      description = ''
        settings.toml keys (OmniWM's settings reference:
        https://omniwm.app/config/settings-reference/), table by table, merged
        into OmniWM's own file. Use floats where OmniWM reads floats (8.0,
        not 8).
      '';
    };
    hotkeys = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        "focus.left" = "Option+H";
      };
      description = ''
        Action id → binding ("Control+Option+Shift+Command+Key", key names as
        OmniWM writes them: "Left Arrow", "Return", "Page Up"…, or
        "Unassigned"). An action already on that chord is unassigned.
        `openApp.<bundle id>` opens (or focuses) an app.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.omniwm = {
      enable = true;
      # Empty: the module would link a read-only settings.toml (see above).
      settings = { };
    };

    customHomeManagerModules.omniwmConfig = {
      # niri's layout (homeManagerModules/niri/niriConfig.nix).
      settings = defaults {
        gaps.size = 10.0;
        focus.followsMouse = true;
        niri = {
          centerFocusedColumn = "never";
          containerPrimarySpanPresets = [
            (1.0 / 3.0)
            0.5
            (2.0 / 3.0)
            0.8
          ];
          defaultContainerPrimarySpan = 0.8;
        };
        borders.width = 2.0;
        # Option+Q's history (niri: Mod+Q, the clipboard manager).
        clipboard.historyEnabled = true;
        # Updates come with nixbook (the app in the store can't replace itself).
        general.updateChecksEnabled = false;
      };
      hotkeys = defaults {
        # Applications & shell
        "openApp.net.kovidgoyal.kitty" = "Option+Return";
        "openCommandPalette.applications" = "Option+D";
        "openCommandPalette.clipboard" = "Option+Q";
        "toggleWorkspaceBarVisibility" = "Option+B";
        "toggleOverview" = "Option+Tab";
        # Window management
        "closeFocusedWindow" = "Option+A";
        "toggleFullscreen" = "Option+F";
        "toggleContainerFullPrimarySpan" = "Option+Z";
        "centerColumn" = "Option+C";
        "cycleSizeForward" = "Option+R";
        # Focus: columns left/right, workspaces up/down, windows of a column
        "focus.left" = "Option+Left Arrow";
        "focus.right" = "Option+Right Arrow";
        "switchWorkspace.previous" = "Option+Up Arrow";
        "switchWorkspace.next" = "Option+Down Arrow";
        "focus.up" = "Control+Option+Up Arrow";
        "focus.down" = "Control+Option+Down Arrow";
        # Moving: columns, columns to workspaces, windows within/out of columns
        "moveColumn.left" = "Option+Shift+Left Arrow";
        "moveColumn.right" = "Option+Shift+Right Arrow";
        "moveColumnToWorkspaceUp" = "Option+Shift+Up Arrow";
        "moveColumnToWorkspaceDown" = "Option+Shift+Down Arrow";
        "move.left" = "Control+Option+Shift+Left Arrow";
        "move.right" = "Control+Option+Shift+Right Arrow";
        "move.up" = "Control+Option+Shift+Up Arrow";
        "move.down" = "Control+Option+Shift+Down Arrow";
        # Monitors (niri: Ctrl+Alt+arrows)
        "focusMonitorPrevious" = "Control+Option+Left Arrow";
        "focusMonitorNext" = "Control+Option+Right Arrow";
        "moveWindowToMonitor.left" = "Control+Option+Shift+Page Up";
        "moveWindowToMonitor.right" = "Control+Option+Shift+Page Down";
      };
    };

    home.activation.omniwmSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      run ${apply}
    '';

    launchd.agents.omniwm-nix-settings = {
      enable = true;
      config = {
        ProgramArguments = [ "${apply}" ];
        WatchPaths = [ settingsFile ];
        RunAtLoad = true;
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/omniwm-nix-settings.log";
      };
    };
  };
}
