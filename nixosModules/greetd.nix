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
        Whether to enable the greetd display manager with tuigreet.

        Configures greetd to launch tuigreet, a TUI-based greeter that:
        - Displays a clock and remembers the last session and user
        - Shows an asterisk-masked password field
        - Presents a user menu for multi-user machines
        - Dynamically builds --sessions from whichever Wayland compositors are
          enabled (niri, sway, hyprland), so only installed sessions appear
        - Wraps niri sessions via niri-session for proper environment setup
        - Enables U2F authentication in the greetd PAM service (YubiKey login)

        Depends on at least one compositor module being enabled
        (customNixOSModules.niri, .sway, or .hyprland).
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
