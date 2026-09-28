{
  config,
  lib,
  pkgs,
  ...
}:
# The login screen in nixbook-shell's style: greetd running the shell's own
# greeter (`nixbook-shell greeter`, src/greeter.qml, Quickshell's greetd
# client) in niri — or cage — with one user's look: the theme and variant, the
# palette (the theme's, or the one the shell generates from the wallpaper),
# fonts, account picture and the login screen wallpaper chosen in the shell's
# Settings menu (background.greeterWall, else the lock screen's, else the
# desktop's; per theme variant). tuigreet takes over if neither compositor
# starts, so there is always a login prompt.
#
# The look follows the settings live: nixbook-shell-greeter-theme (run as
# that user, so it only reads what the user can) exports it into
# /var/lib/nixbook-shell-greeter whenever the shell's settings or palette
# change (scripts/greeter-theme.sh). Until it first runs, the greeter uses the
# settings set in Nix.
#
# Authentication is greetd's PAM service (`security.pam.services.greetd`):
# the greeter shows PAM's messages ("touch your security key", fingerprint)
# and answers its prompts, so U2F/fingerprint/keyring setups work as with any
# greetd greeter. It remembers the last user and session
# (/var/cache/nixbook-shell-greeter).
let
  cfg = config.nixbook-shell.greeter;
  stateDir = "/var/lib/nixbook-shell-greeter";
  cacheDir = "/var/cache/nixbook-shell-greeter";
  greeterUser = config.services.greetd.settings.default_session.user;
  greeterGroup = config.users.users.${greeterUser}.group or "greeter";
  # The user whose settings give the look (none: the shell's defaults).
  themed = cfg.user != null;
  home = if themed then config.users.users.${cfg.user}.home or "/home/${cfg.user}" else "/var/empty";
  hmOf = name: if name != null then config.home-manager.users.${name} or { } else { };
  hmUser = hmOf cfg.user;

  # The user's own nixbook-shell (same build as their session), else ours.
  package =
    if hmUser.programs.nixbook-shell.enable or false then
      hmUser.programs.nixbook-shell.package
    else
      (import ./. { inherit pkgs; }).package;

  # A user's cursor (`cursorUser`'s Home Manager home.pointerCursor, e.g.
  # Stylix's or a profile's own).
  cursor =
    let
      pc = (hmOf cfg.cursorUser).home.pointerCursor or null;
    in
    if pc != null && (pc.enable or true) && pc.package or null != null then pc else null;
  cursorEnv = lib.optionalAttrs (cursor != null) {
    XCURSOR_THEME = cursor.name;
    XCURSOR_SIZE = toString cursor.size;
    XCURSOR_PATH = "${cursor.package}/share/icons";
  };

  # The themes and their palettes (checked), from the shell's registry.
  palettes = pkgs.runCommand "nixbook-shell-theme-palettes.json" {
    nativeBuildInputs = [ pkgs.python3 ];
  } "python3 ${./scripts/theme-palettes.py} ${./src/modules/common/themes.json} > $out";
  themeEnv = {
    NB_PALETTES = palettes;
  }
  // lib.optionalAttrs (cfg.background != null) {
    NB_DEFAULT_BACKGROUND = "${cfg.background}";
  };

  # The settings set in Nix for that user (Home Manager as a NixOS module).
  settingsLib = import ./lib.nix { inherit lib; };
  pinned = lib.optionalAttrs themed (
    settingsLib.pinnedSettings (
      lib.attrByPath [ "home-manager" "users" cfg.user "programs" "nixbook-shell" "settings" ] { } config
    )
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

  sessionDirs = "${config.services.displayManager.sessionData.desktops}/share";
  # The sessions this system provides (niri, sway, Hyprland…): [{ name, exec,
  # desktopNames }], Wayland first.
  sessions =
    pkgs.runCommand "nixbook-shell-greeter-sessions.json"
      {
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        python3 - ${sessionDirs} > $out <<'PY'
        import configparser, json, os, sys
        out, seen = [], set()
        for kind in ("wayland-sessions", "xsessions"):
            d = os.path.join(sys.argv[1], kind)
            for f in sorted(os.listdir(d)) if os.path.isdir(d) else []:
                if not f.endswith(".desktop"):
                    continue
                p = configparser.ConfigParser(interpolation=None, strict=False)
                p.optionxform = str
                p.read(os.path.join(d, f), encoding="utf-8")
                e = p["Desktop Entry"] if p.has_section("Desktop Entry") else {}
                name, exe = e.get("Name", ""), e.get("Exec", "")
                if not name or not exe or name in seen or e.get("Hidden") == "true" or e.get("NoDisplay") == "true":
                    continue
                seen.add(name)
                out.append({"name": name, "exec": exe, "desktopNames": e.get("DesktopNames", "").replace(";", ":").strip(":")})
        json.dump(out, sys.stdout)
        PY
      '';
  # The accounts that can log in (normal users), the login screen's first.
  users = lib.sort (a: b: themed && a.name == cfg.user && b.name != cfg.user) (
    lib.mapAttrsToList (name: u: {
      inherit name;
      realName = u.description or "";
    }) (lib.filterAttrs (_: u: u.isNormalUser or false) config.users.users)
  );
  usersJson = pkgs.writeText "nixbook-shell-greeter-users.json" (builtins.toJSON users);

  # Runs as the greeter user in the compositor: a private copy of the
  # exported settings (else the ones from Nix) as the shell's config, the
  # wallpaper, and the users/sessions list, then the greeter.
  greeterRun = pkgs.writeShellScript "nixbook-shell-greeter-run" ''
    export PATH=${
      lib.makeBinPath [
        pkgs.jq
        pkgs.coreutils
      ]
    }''${PATH:+:$PATH}
    src=${stateDir}
    [ -s "$src/settings.json" ] || src=${fallbackTheme}
    wall=""
    if [ -s ${stateDir}/background ]; then
      wall=${stateDir}/background
    ${lib.optionalString (cfg.background != null) ''
      else
        wall=${cfg.background}
    ''}
    fi
    run=$(mktemp -d "''${XDG_RUNTIME_DIR:-/tmp}/nixbook-shell-greeter.XXXXXX")
    mkdir -p "$run/config/nixbook-shell" "$run/state/quickshell/user/generated" "$run/cache"
    jq --arg wall "$wall" '. + {background: {wallpaperPath: $wall}}' "$src/settings.json" \
      >"$run/config/nixbook-shell/config.json"
    cp "$src/colors.json" "$run/state/quickshell/user/generated/colors.json" 2>/dev/null || true
    avatar=""
    [ -s ${stateDir}/avatar ] && avatar=${stateDir}/avatar
    jq -n --slurpfile users ${usersJson} --slurpfile sessions ${sessions} \
      --arg avatar "$avatar" --arg me ${lib.escapeShellArg (if themed then cfg.user else "")} '{
        users: ($users[0] | map(if .name == $me and $avatar != "" then . + {avatar: $avatar} else . end)),
        sessions: $sessions[0],
        defaultUser: (if $me != "" then $me else ($users[0][0].name // "") end),
        cache: "${cacheDir}/last.json"
      }' >"$run/info.json"
    export XDG_CONFIG_HOME="$run/config" XDG_STATE_HOME="$run/state" XDG_CACHE_HOME="$run/cache"
    export NB_GREETER_INFO="$run/info.json"
    ${lib.concatStrings (lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}\n") cursorEnv)}
    exec ${lib.getExe package} greeter
  '';

  # niri as the greeter's compositor: its very first frame is the theme's
  # background colour, swaybg puts the wallpaper up a few milliseconds later,
  # then the greeter (the same wallpaper under its login card) comes up over
  # it; every screen shows the wallpaper. The greeter exiting (a session was
  # started) ends niri.
  niri = config.programs.niri.package or pkgs.niri;
  niriSession = pkgs.writeShellScript "nixbook-shell-greeter-in-niri" ''
    ${greeterRun}
    exec ${lib.getExe niri} msg action quit --skip-confirmation
  '';
  kdlXkb = lib.concatStrings (
    lib.mapAttrsToList (k: v: lib.optionalString (v != "") "            ${k} ${builtins.toJSON v}\n") {
      inherit (cfg.keyboard) layout variant options;
    }
  );
  kdlCursor = lib.optionalString (cursor != null) ''
    cursor {
        xcursor-theme ${builtins.toJSON cursor.name}
        xcursor-size ${toString cursor.size}
    }
  '';
  # @BG@, @WALLPAPER@: filled in at start (the exported look).
  niriTemplate = pkgs.writeText "nixbook-shell-greeter-niri.kdl" ''
    input {
        keyboard {
            xkb {
    ${kdlXkb}        }
        }
        touchpad {
            tap
        }
    }
    layout {
        background-color "@BG@"
    }
    hotkey-overlay {
        skip-at-startup
    }
    prefer-no-csd
    ${kdlCursor}
    @WALLPAPER@
    spawn-at-startup "${niriSession}"
  '';
  # Fails the build if niri would reject the configuration.
  niriTemplateChecked = pkgs.runCommand "nixbook-shell-greeter-niri-checked.kdl" { } ''
    t=$(<${niriTemplate})
    t=''${t//@BG@/#000000}
    t=''${t//@WALLPAPER@/spawn-at-startup \"${lib.getExe pkgs.swaybg}\" \"-i\" \"/wallpaper\"}
    printf '%s\n' "$t" >check.kdl
    ${lib.getExe niri} validate -c check.kdl
    cp ${niriTemplate} $out
  '';

  xkb = lib.filterAttrs (_: v: v != "") {
    XKB_DEFAULT_LAYOUT = cfg.keyboard.layout;
    XKB_DEFAULT_VARIANT = cfg.keyboard.variant;
    XKB_DEFAULT_OPTIONS = cfg.keyboard.options;
  };
  exports = lib.concatStrings (
    lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}\n") (xkb // cursorEnv)
  );

  greeterCommand = pkgs.writeShellScript "nixbook-shell-greeter" ''
    ${exports}
    # niri first (the smooth start), cage if it can't run, tuigreet if
    # neither can — but not when greetd itself is stopping us.
    stopping=""
    trap 'stopping=1' TERM INT HUP
    ${lib.optionalString (cfg.compositor == "niri") ''
      src=${stateDir}
      [ -s "$src/bg" ] || src=${fallbackTheme}
      bg=$(${pkgs.coreutils}/bin/head -c 9 "$src/bg" 2>/dev/null)
      case "$bg" in \#[0-9a-fA-F]*) ;; *) bg="#000000" ;; esac
      wallpaper=""
      wall=""
      [ -s ${stateDir}/background ] && wall=${stateDir}/background
      ${lib.optionalString (cfg.background != null) ''[ -n "$wall" ] || wall=${cfg.background}''}
      [ -n "$wall" ] &&
        wallpaper="spawn-at-startup \"${lib.getExe pkgs.swaybg}\" \"-m\" \"fill\" \"-i\" \"$wall\""
      t=$(<${niriTemplateChecked})
      t=''${t//@BG@/$bg}
      t=''${t//@WALLPAPER@/$wallpaper}
      dir=''${XDG_RUNTIME_DIR:-$(${pkgs.coreutils}/bin/mktemp -d)}
      printf '%s\n' "$t" >"$dir/nixbook-shell-greeter-niri.kdl"
      ${lib.getExe niri} -c "$dir/nixbook-shell-greeter-niri.kdl" && exit 0
      [ -z "$stopping" ] || exit 0
    ''}
    ${lib.getExe pkgs.cage} -s -- ${greeterRun} && exit 0
    [ -z "$stopping" ] || exit 0
    exec ${lib.getExe pkgs.tuigreet} --time --remember --remember-session --asterisks \
      --sessions ${sessionDirs}/wayland-sessions:${sessionDirs}/xsessions
  '';
in
{
  options.nixbook-shell.greeter = {
    enable = lib.mkEnableOption ''
      the login screen in nixbook-shell's style: greetd with the shell's own
      greeter, given its look and wallpaper by `user`'s nixbook-shell settings'';

    user = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "alice";
      description = ''
        The user whose nixbook-shell settings (theme and variant, wallpaper
        palette, login screen wallpaper, account picture) the login screen
        follows, and the one it offers first. null: the shell's default look
        (no one on the machine needs to run nixbook-shell).
      '';
    };

    cursorUser = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = cfg.user;
      defaultText = lib.literalExpression "config.nixbook-shell.greeter.user";
      example = "alice";
      description = ''
        The user whose cursor (Home Manager's `home.pointerCursor`) the login
        screen shows. null: the compositor's default.
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

    compositor = lib.mkOption {
      type = lib.types.enum [
        "niri"
        "cage"
      ];
      default = if config.programs.niri.enable or false then "niri" else "cage";
      defaultText = lib.literalExpression ''if config.programs.niri.enable then "niri" else "cage"'';
      description = ''
        Compositor the greeter runs in. niri shows the theme's background and
        the wallpaper from its first frames; cage is black until the greeter
        has drawn. Either way tuigreet takes over if it can't start.
      '';
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
        assertion = !themed || config.users.users ? ${cfg.user};
        message = "nixbook-shell.greeter.user: no user `${toString cfg.user}`.";
      }
    ];

    services.greetd = {
      enable = true;
      settings.default_session.command = "${pkgs.dbus}/bin/dbus-run-session ${greeterCommand}";
    };
    # The theme's fonts, for the greeter (it has none of the user's).
    fonts.packages = [
      pkgs.roboto
      pkgs.oswald
      pkgs.nunito
    ];

    # Boot splash to login screen without a black screen or console in
    # between: greetd, not plymouth-quit.service, ends the splash, leaving its
    # last frame on screen (--retain-splash) until the greeter's compositor
    # draws over it — what GDM does.
    services.greetd.greeterManagesPlymouth = lib.mkIf config.boot.plymouth.enable true;
    systemd.services.greetd = lib.mkIf config.boot.plymouth.enable {
      conflicts = [ "plymouth-quit.service" ];
      after = [
        "plymouth-quit.service"
        "plymouth-start.service"
      ];
      onFailure = [ "plymouth-quit.service" ];
      serviceConfig.ExecStartPre = [
        "-${config.boot.plymouth.package}/bin/plymouth quit --retain-splash"
      ];
    };

    # Owned by the user (the renderer runs as them), readable by the greeter.
    systemd.tmpfiles.rules =
      lib.optional themed "d ${stateDir} 0750 ${cfg.user} ${greeterGroup} - -"
      # The greeter's own: the last user and session.
      ++ [ "d ${cacheDir} 0750 ${greeterUser} ${greeterGroup} - -" ];

    systemd.services.nixbook-shell-greeter-theme = lib.mkIf themed {
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
    systemd.paths.nixbook-shell-greeter-theme = lib.mkIf themed {
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
