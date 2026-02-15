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
        default_session = {
          command =
            let
              sessionPaths = lib.concatLists [
                (lib.optionals cfg.niri.enable [ "${pkgs.niri}/share/wayland-sessions" ])
                (lib.optionals cfg.sway.enable [ "${pkgs.swayfx}/share/wayland-sessions" ])
                (lib.optionals cfg.hyprland.enable [ "${pkgs.hyprland}/share/wayland-sessions" ])
              ];
              sessionsArg = lib.optionalString (
                sessionPaths != [ ]
              ) "--sessions ${lib.concatStringsSep ":" sessionPaths}";
              wrapperArg = lib.optionalString cfg.niri.enable "--session-wrapper '${pkgs.niri}/bin/niri-session'";
            in
            ''
              ${pkgs.tuigreet}/bin/tuigreet \
                --time \
                --remember-session \
                --remember \
                --asterisks \
                --user-menu \
                ${sessionsArg} \
                ${wrapperArg}
            '';
        };
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
