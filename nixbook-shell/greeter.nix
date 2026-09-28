{
  config,
  lib,
  pkgs,
  ...
}:
# The login screen in nixbook-shell's style: greetd + ReGreet (the maintained
# GTK4 greetd greeter, nixpkgs' services.displayManager.regreet) in cage,
# themed from one user's nixbook-shell settings — the Material palette the
# shell generates from the wallpaper, or the Persona style and variant — and
# showing the login screen wallpaper chosen in the shell's Settings menu
# (Background > Wallpaper, "Login screen": background.greeterWall, else the
# lock screen's, else the desktop's).
#
# The theme follows the settings live: nixbook-shell-greeter-theme (run as
# that user, so it only reads what the user can) renders it into
# /var/lib/nixbook-shell-greeter whenever the shell's settings or palette
# change (scripts/greeter-theme.sh). Until it first runs, the greeter uses the
# same theme built from the settings set in Nix.
#
# Authentication is greetd's PAM service (`security.pam.services.greetd`):
# ReGreet shows PAM's messages ("touch your security key", fingerprint
# prompts) and answers them, so U2F/fingerprint/keyring setups work as with
# any greetd greeter.
let
  cfg = config.nixbook-shell.greeter;
  regreet = config.services.displayManager.regreet;
  stateDir = "/var/lib/nixbook-shell-greeter";
  greeterUser = config.services.greetd.settings.default_session.user;
  greeterGroup = config.users.users.${greeterUser}.group or "greeter";
  home = config.users.users.${cfg.user}.home or "/home/${cfg.user}";

  # Persona art, rasterised with the shell (qml.nix).
  shell = import ./qml.nix { inherit pkgs; };
  palettes = pkgs.runCommand "nixbook-shell-persona-palettes.json" {
    nativeBuildInputs = [ pkgs.python3 ];
  } "python3 ${./scripts/persona-palettes.py} ${./src/modules/common/Persona.qml} > $out";
  themeEnv = {
    NB_PALETTES = palettes;
    NB_TEXTURES = "${shell}/assets/persona";
  }
  // lib.optionalAttrs (cfg.background != null) {
    NB_DEFAULT_BACKGROUND = "${cfg.background}";
  };

  # The settings set in Nix for that user (Home Manager as a NixOS module).
  settingsLib = import ./lib.nix { inherit lib; };
  pinned = settingsLib.setLeaves (
    lib.attrByPath [ "home-manager" "users" cfg.user "programs" "nixbook-shell" "settings" ] { } config
  );
  fallbackTheme =
    pkgs.runCommand "nixbook-shell-greeter-theme"
      (
        themeEnv
        // {
          nativeBuildInputs = [ pkgs.jq ];
          NB_CONFIG = pkgs.writeText "nixbook-shell-pinned.json" (builtins.toJSON pinned);
        }
      )
      ''
        NB_OUT=$out bash ${./scripts/greeter-theme.sh}
      '';

  renderTheme = pkgs.writeShellScript "nixbook-shell-greeter-theme" ''
    export PATH=${
      lib.makeBinPath [
        pkgs.jq
        pkgs.coreutils
        pkgs.ffmpeg-headless
      ]
    }
    ${lib.concatStrings (lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}\n") themeEnv)}
    export NB_CONFIG=${lib.escapeShellArg "${home}/.config/nixbook-shell/config.json"}
    export NB_COLORS=${lib.escapeShellArg "${home}/.local/state/quickshell/user/generated/colors.json"}
    export NB_OUT=${stateDir}
    export NB_COPY_BACKGROUND=1
    exec ${pkgs.bash}/bin/bash ${./scripts/greeter-theme.sh}
  '';

  toml = pkgs.formats.toml { };
  # Two configurations, the same but for the wallpaper: the rendered one, or
  # the NixOS option's (none: the theme's background colour) before the first
  # render.
  regreetConfig =
    background:
    toml.generate "regreet.toml" (
      lib.recursiveUpdate regreet.settings (
        lib.optionalAttrs (background != null) { background.path = background; }
      )
    );
  liveConfig = regreetConfig "${stateDir}/background";
  staticConfig = regreetConfig (if cfg.background != null then "${cfg.background}" else null);

  greeter = pkgs.writeShellScript "nixbook-shell-greeter" ''
    css=${stateDir}/regreet.css
    [ -s "$css" ] || css=${fallbackTheme}/regreet.css
    conf=${staticConfig}
    [ -s ${stateDir}/background ] && conf=${liveConfig}
    # Only the sessions this system provides (niri, sway, Hyprland…), found
    # first; ReGreet skips duplicates.
    export XDG_DATA_DIRS="${config.services.displayManager.sessionData.desktops}/share''${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"
    exec ${lib.getExe regreet.package} --config "$conf" --style "$css"
  '';

  xkb = lib.filterAttrs (_: v: v != "") {
    XKB_DEFAULT_LAYOUT = cfg.keyboard.layout;
    XKB_DEFAULT_VARIANT = cfg.keyboard.variant;
    XKB_DEFAULT_OPTIONS = cfg.keyboard.options;
  };
in
{
  options.nixbook-shell.greeter = {
    enable = lib.mkEnableOption ''
      the login screen in nixbook-shell's style: greetd with ReGreet, themed
      and given its wallpaper from `user`'s nixbook-shell settings'';

    user = lib.mkOption {
      type = lib.types.str;
      example = "alice";
      description = ''
        The user whose nixbook-shell settings (Persona style and variant,
        wallpaper palette, login screen wallpaper) the login screen follows.
      '';
    };

    background = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = lib.literalExpression "./wallpapers/login.jpg";
      description = ''
        Login screen wallpaper when none is chosen in the shell
        (`background.greeterWall`, Settings > Background > Login screen);
        before the lock screen's and the desktop's.
      '';
    };

    greeting = lib.mkOption {
      type = lib.types.str;
      default = "Welcome back";
      description = "Message shown above the login form.";
    };

    keyboard = {
      layout = lib.mkOption {
        type = lib.types.str;
        default = config.services.xserver.xkb.layout;
        defaultText = lib.literalExpression "config.services.xserver.xkb.layout";
        description = "XKB layout the password is typed with.";
      };
      variant = lib.mkOption {
        type = lib.types.str;
        default = config.services.xserver.xkb.variant;
        defaultText = lib.literalExpression "config.services.xserver.xkb.variant";
        description = "XKB variant.";
      };
      options = lib.mkOption {
        type = lib.types.str;
        default = config.services.xserver.xkb.options;
        defaultText = lib.literalExpression "config.services.xserver.xkb.options";
        description = "XKB options.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.users.users ? ${cfg.user};
        message = "nixbook-shell.greeter.user: no user `${cfg.user}`.";
      }
    ];

    services.displayManager.regreet = {
      enable = true;
      settings = {
        background.fit = "Cover";
        GTK.application_prefer_dark_theme = true;
        appearance.greeting_msg = cfg.greeting;
        widget.clock = {
          format = "%A %d %B   %H:%M";
          resolution = "500ms";
        };
      };
      # Body text; titles use the shell's display face (Oswald in the Persona
      # style), from the stylesheet.
      font = {
        package = pkgs.roboto;
        name = "Roboto";
        size = 13;
      };
      iconTheme = {
        package = pkgs.papirus-icon-theme;
        name = "Papirus-Dark";
      };
    };
    fonts.packages = [ pkgs.oswald ];

    # ReGreet in cage, with the keyboard layout of the system (cage reads
    # XKB_DEFAULT_*), the rendered theme and the sessions above.
    services.greetd.settings.default_session.command = lib.concatStringsSep " " (
      [ "${pkgs.dbus}/bin/dbus-run-session" ]
      ++ lib.optionals (xkb != { }) (
        [ "${pkgs.coreutils}/bin/env" ] ++ lib.mapAttrsToList (k: v: lib.escapeShellArg "${k}=${v}") xkb
      )
      ++ [
        (lib.getExe pkgs.cage)
        (lib.escapeShellArgs regreet.cageArgs)
        "--"
        "${greeter}"
      ]
    );

    # Owned by the user (the renderer runs as them), readable by the greeter.
    systemd.tmpfiles.rules = [
      "d ${stateDir} 0750 ${cfg.user} ${greeterGroup} - -"
    ];

    systemd.services.nixbook-shell-greeter-theme = {
      description = "Login screen theme from ${cfg.user}'s nixbook-shell settings";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-tmpfiles-setup.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        ExecStart = renderTheme;
        UMask = "0022";
        # Reads the user's settings, writes the state directory, nothing else.
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths = [ stateDir ];
        PrivateTmp = true;
        PrivateNetwork = true;
        PrivateDevices = true;
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
        RestrictAddressFamilies = "none";
        RestrictNamespaces = true;
        LockPersonality = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        SystemCallArchitectures = "native";
      };
    };
    # Re-rendered when the shell rewrites its settings or its palette (a new
    # wallpaper, Persona on/off, another variant or login screen wallpaper).
    systemd.paths.nixbook-shell-greeter-theme = {
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathChanged = [
          "${home}/.config/nixbook-shell/config.json"
          "${home}/.local/state/quickshell/user/generated/colors.json"
        ];
        Unit = "nixbook-shell-greeter-theme.service";
      };
    };

    # Lets the shell's Settings menu offer the login screen wallpaper.
    environment.etc."nixbook-shell/greeter.json".text = builtins.toJSON {
      inherit (cfg) user;
      background = if cfg.background != null then "${cfg.background}" else "";
    };
  };
}
