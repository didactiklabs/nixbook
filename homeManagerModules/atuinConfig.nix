{
  config,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules;
in
{
  config = lib.mkIf cfg.atuinConfig.didactiklabs.enable {
    programs = {
      atuin = {
        enable = true;
        daemon.enable = true;
        settings = {
          sync_address = "https://atuin.didactik.labs";
          enter_accept = true;
          sync = {
            records = true;
          };
        };
      };
    };
  };

  options.customHomeManagerModules.atuinConfig = {
    didactiklabs.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable Atuin shell history sync against the DidactikLabs server.

        Atuin replaces the standard shell history with a searchable, syncable
        SQLite database.  The base atuin program is always enabled via
        commonShellConfig; this option additionally configures:
          - sync_address: https://atuin.didactik.labs (private DidactikLabs instance)
          - enter_accept: pressing Enter on a selected history item runs it immediately
          - sync.records: enables the newer record-based sync protocol

        Enable this on machines that belong to the DidactikLabs environment and
        where you want cross-machine shell history synchronisation.
        Requires the Atuin account to be set up via `atuin register` / `atuin login`.
      '';
    };
  };
}
