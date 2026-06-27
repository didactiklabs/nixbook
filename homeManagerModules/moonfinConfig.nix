{
  config,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules;
in
{
  options.customHomeManagerModules.moonfinConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable Moonfin (Jellyfin/Emby client) configuration.

        Deploys settings so the app connects to the configured server
        automatically on launch.
      '';
    };

    serverUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://jellyfin.bealv.io";
      description = "Jellyfin/Emby server URL to connect to.";
    };
  };

  config = lib.mkIf cfg.moonfinConfig.enable {
    # Moonfin is a Flutter app that uses shared_preferences for persistence.
    # On Linux, shared_preferences stores data in
    # $XDG_CONFIG_HOME/<app-name>.json (typically ~/.config/Moonfin.json).
    #
    # The exact key names depend on the Moonfin source code. Common keys for
    # Flutter shared_preferences include string values stored as JSON.
    # We deploy the server URL here; if the key name doesn't match, the user
    # will need to enter the URL manually on first launch.
    xdg.configFile."Moonfin/settings.json".text = builtins.toJSON {
      serverUrl = cfg.moonfinConfig.serverUrl;
    };
  };
}
