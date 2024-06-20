{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customNixOSModules.greetd;
in {
  options.customNixOSModules.greetd = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable greeter globally or not.
      '';
    };
  };
  config = lib.mkIf cfg.enable {
    services.greetd = {
      enable = true;
      vt = 7; ## tty to skip startup msgs
      settings = {
        default_session.command = ''
          ${pkgs.greetd.tuigreet}/bin/tuigreet \
            --issue \
            --time \
            --remember-session \
            --remember \
            --asterisks \
            --user-menu \
            --cmd ${pkgs.swayfx}/bin/sway
        '';
      };
    };
    environment.etc."greetd/environments".text = ''
      ${pkgs.swayfx}/bin/sway
    '';
  };
}
