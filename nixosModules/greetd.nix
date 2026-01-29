{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customNixOSModules;
in
{
  options.customNixOSModules.greetd = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable greeter globally or not.
      '';
    };
  };
  config = lib.mkIf cfg.greetd.enable {
    services.greetd = {
      enable = true;
      settings = {
        default_session.command = ''
          ${pkgs.tuigreet}/bin/tuigreet \
            --time \
            --remember-session \
            --remember \
            --asterisks \
            --user-menu
        '';
      };
    };
    security = {
      pam.services = {
        # yubikey login
        greetd.u2fAuth = true;
      };
    };
  };
}
