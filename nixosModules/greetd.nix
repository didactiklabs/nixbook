{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customNixOSModules;
  sessionPaths = lib.concatLists [
    (lib.optionals cfg.niri.enable [ "${pkgs.niri}/share/wayland-sessions" ])
    (lib.optionals cfg.sway.enable [ "${pkgs.swayfx}/share/wayland-sessions" ])
    (lib.optionals cfg.hyprland.enable [ "${pkgs.hyprland}/share/wayland-sessions" ])
  ];
  # The first user running nixbook-shell: the login screen follows their
  # shell settings.
  shellUsers = lib.filter (u: config.home-manager.users.${u}.programs.nixbook-shell.enable or false) (
    lib.attrNames (config.home-manager.users or { })
  );
in
{
  options.customNixOSModules.greetd = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable the greetd display manager.

        The greeter is chosen with `greeter`:
        - `tuigreet` (default): a TUI greeter with a clock, the last session
          and user remembered, an asterisk-masked password field and a user
          menu. Its --sessions are built from whichever Wayland compositors
          are enabled (niri, sway, hyprland), niri sessions are wrapped with
          niri-session.
        - `nixbook-shell`: ReGreet (GTK4, in cage) in nixbook-shell's style,
          following a user's shell settings: Material palette from the
          wallpaper or the Persona style and variant, and the login screen
          wallpaper chosen in the shell's Settings menu
          (`nixbook-shell.greeter`, nixbook-shell/greeter.nix). It also
          remembers the last user and session, and lists the sessions of the
          enabled compositors.

        Either way the greetd PAM service has U2F (YubiKey), fingerprint and
        GNOME Keyring unlock; both greeters show PAM's prompts ("touch your
        security key", fingerprint).

        Depends on at least one compositor module being enabled
        (customNixOSModules.niri, .sway, or .hyprland).
      '';
    };
    greeter = lib.mkOption {
      type = lib.types.enum [
        "tuigreet"
        "nixbook-shell"
      ];
      default = "tuigreet";
      description = "The greeter greetd runs (see `enable`).";
    };
    themeUser = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = if shellUsers != [ ] then lib.head shellUsers else null;
      defaultText = lib.literalExpression "the first Home Manager user with programs.nixbook-shell enabled";
      description = ''
        With the `nixbook-shell` greeter: the user whose nixbook-shell
        settings the login screen follows.
      '';
    };
  };
  config = lib.mkIf cfg.greetd.enable (
    lib.mkMerge [
      {
        services.greetd.enable = true;
        security = {
          pam.services = {
            greetd = {
              u2fAuth = true;
              fprintAuth = true;
              enableGnomeKeyring = true;
            };
          };
        };
      }
      (lib.mkIf (cfg.greetd.greeter == "tuigreet") {
        services.greetd.settings.default_session.command =
          let
            sessionsArg = lib.optionalString (
              sessionPaths != [ ]
            ) "--sessions ${lib.concatStringsSep ":" sessionPaths}";
            wrapperArg = lib.optionalString cfg.niri.enable "--session-wrapper '${pkgs.niri}/bin/niri-session'";
          in
          lib.concatStringsSep " " (
            lib.filter (s: s != "") [
              "${pkgs.tuigreet}/bin/tuigreet"
              "--time"
              "--remember-session"
              "--remember"
              "--asterisks"
              "--user-menu"
              sessionsArg
              wrapperArg
            ]
          );
      })
      (lib.mkIf (cfg.greetd.greeter == "nixbook-shell") {
        assertions = [
          {
            assertion = cfg.greetd.themeUser != null;
            message = ''
              customNixOSModules.greetd.greeter = "nixbook-shell" needs a user running
              nixbook-shell (customHomeManagerModules.nixbookShellConfig), or
              customNixOSModules.greetd.themeUser set.
            '';
          }
        ];
        nixbook-shell.greeter = lib.mkIf (cfg.greetd.themeUser != null) {
          enable = true;
          user = cfg.greetd.themeUser;
        };
      })
    ]
  );
}
