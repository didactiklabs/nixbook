{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules.thunderbirdConfig;
in
{
  options.customHomeManagerModules.thunderbirdConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable Mozilla Thunderbird email client.

        Installs and manages the Thunderbird email/calendar client via
        Home Manager's programs.thunderbird module.  Account configuration
        and profiles are managed manually through the Thunderbird UI (not
        declaratively, as mail credentials are sensitive).

        Telemetry and health reports to Mozilla are switched off in every
        declared profile.

        Used on: totoro, nishinoya.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.thunderbird = {
      enable = true;
      package = pkgs.thunderbird;
      # Applied to every profile Home Manager manages (user.js).
      settings = {
        "toolkit.telemetry.enabled" = false;
        "toolkit.telemetry.unified" = false;
        "toolkit.telemetry.archive.enabled" = false;
        "datareporting.healthreport.uploadEnabled" = false;
        "datareporting.policy.dataSubmissionEnabled" = false;
      };
    };
  };
}
