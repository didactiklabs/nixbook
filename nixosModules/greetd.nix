{ config, pkgs, lib, ... }:
let cfg = config.customNixOSModules;
in {
  options.customNixOSModules.greetd = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        whether to enable greeter globally or not.
      '';
    };
  };
  config = lib.mkIf cfg.greetd.enable {
    services.greetd = {
      enable = true;
      vt = 7; # # tty to skip startup msgs
      settings = {
        default_session.command = ''
          ${pkgs.greetd.tuigreet}/bin/tuigreet \
            --time \
            --remember-session \
            --remember \
            --asterisks \
            --user-menu
        '';
      };
    };
  };
}
