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

        The greeter is chosen with `greeter` (by default nixbook-shell's
        login screen when a user runs nixbook-shell, else tuigreet):
        - `tuigreet`: a TUI greeter with a clock, the last session
          and user remembered, an asterisk-masked password field and a user
          menu. Its --sessions are built from whichever Wayland compositors
          are enabled (niri, sway), niri sessions are wrapped with
          niri-session.
        - `nixbook-shell`: nixbook-shell's own login screen (Quickshell,
          in niri or cage) following a user's shell settings: the theme and
          variant (Material palette from the wallpaper, Persona, Chiikawa…),
          fonts, account picture, cursor and the login screen wallpaper chosen
          in the shell's Settings menu (`nixbook-shell.greeter`,
          nixbook-shell/greeter.nix). It remembers the last user and session,
          lists the sessions of the enabled compositors, and falls back to
          tuigreet if it can't start.

        Either way the greetd PAM service has U2F (YubiKey), fingerprint and
        GNOME Keyring unlock; both greeters show PAM's prompts ("touch your
        security key", fingerprint).

        Depends on at least one compositor module being enabled
        (customNixOSModules.niri or .sway).
      '';
    };
    greeter = lib.mkOption {
      type = lib.types.enum [
        "tuigreet"
        "nixbook-shell"
      ];
      # A machine whose users run nixbook-shell gets its login screen too.
      default = if shellUsers != [ ] then "nixbook-shell" else "tuigreet";
      defaultText = lib.literalExpression ''"nixbook-shell" when a Home Manager user has programs.nixbook-shell enabled, else "tuigreet"'';
      description = "The greeter greetd runs (see `enable`).";
    };
    cursorUser = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default =
        if cfg.greetd.themeUser != null then
          cfg.greetd.themeUser
        else
          lib.findFirst (u: config.home-manager.users.${u}.home.pointerCursor.enable or false) null (
            lib.attrNames (config.home-manager.users or { })
          );
      defaultText = lib.literalExpression "themeUser, else the first Home Manager user with a pointer cursor";
      description = ''
        With the `nixbook-shell` greeter: the user whose cursor
        (home.pointerCursor) the login screen shows.
      '';
    };
    themeUser = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = if shellUsers != [ ] then lib.head shellUsers else null;
      defaultText = lib.literalExpression "the first Home Manager user with programs.nixbook-shell enabled";
      description = ''
        With the `nixbook-shell` greeter: the user whose nixbook-shell
        settings the login screen follows (null: the shell's default look,
        e.g. on a machine whose users run DankMaterialShell).
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
        nixbook-shell.greeter = {
          enable = true;
          # null (no one runs nixbook-shell): the shell's default look.
          user = cfg.greetd.themeUser;
          cursorUser = cfg.greetd.cursorUser;
        };
      })
    ]
  );
}
