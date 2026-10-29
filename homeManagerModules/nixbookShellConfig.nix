{
  config,
  options,
  pkgs,
  lib,
  osConfig ? null,
  ...
}:
# nixbook's side of nixbook-shell (nixbook-shell/, a self-contained package +
# Home Manager module `programs.nixbook-shell`): the nixbookShellConfig toggle,
# the settings shared by every nixbook machine, the repository's quickshell
# pin, and the machine context (hosts, modules, colmena) for the shell's
# assistants.
let
  cfg = config.customHomeManagerModules.nixbookShellConfig;
  sources = import ../npins;

  os = osConfig;
  hostName = if os != null then os.networking.hostName else "unknown";
  user = config.home.username;
  enabledIn =
    set:
    lib.sort lib.lessThan (
      lib.attrNames (lib.filterAttrs (_: v: builtins.isAttrs v && (v.enable or false) == true) set)
    );
  declared = set: lib.sort lib.lessThan (lib.attrNames set);
  names = pkgList: lib.unique (lib.sort lib.lessThan (map lib.getName pkgList));
  osModules = if os != null then enabledIn (os.customNixOSModules or { }) else [ ];
  hmModules = enabledIn (config.customHomeManagerModules or { });
  niriEnabled = config.customHomeManagerModules.niriConfig.enable or false;
  # Music apps the AI chat gets an MCP server for, where they're installed.
  # Matched by name, not by derivation: a wrapped or overridden copy (e.g.
  # lib/electronA11y.nix's "pear-desktop-a11y" or "pear-desktop-bridged") is
  # still the app — comparing derivations silently dropped the YouTube Music
  # server where it was wrapped.
  installed = name: lib.any (p: lib.hasPrefix name (lib.getName p)) config.home.packages;
  # jellyfinMcp.enable / player.enable: null = automatic.
  jellyfinOn = if cfg.jellyfinMcp.enable != null then cfg.jellyfinMcp.enable else installed "moonfin";
  jellyfinPlayerOn =
    if cfg.jellyfinMcp.player.enable != null then cfg.jellyfinMcp.player.enable else jellyfinOn;
  # seerrMcp.enable: null = with Jellyfin's (a Seerr requests into it).
  seerrOn = if cfg.seerrMcp.enable != null then cfg.seerrMcp.enable else jellyfinOn;
  musicMcpServers =
    lib.optionalAttrs (installed "pear-desktop") {
      youtube-music.command = lib.getExe pkgs.customPkgs.youtube-music-mcp;
    }
    // lib.optionalAttrs (installed "spotify") {
      spotify.command = lib.getExe pkgs.customPkgs.spotify-mcp;
    };
  extraMcpServers =
    musicMcpServers
    // lib.optionalAttrs cfg.linkedinMcp.enable {
      linkedin.command = lib.getExe pkgs.customPkgs.linkedin-mcp-server;
    }
    # The phone through KDE Connect, for the side panel's Claude only: not on
    # the PATH, so no other agent gets it. Reading its texts and
    # notifications is a separate switch (ai.phone.readMessages, off).
    // lib.optionalAttrs config.services.kdeconnect.enable {
      phone.command = lib.getExe pkgs.customPkgs.kdeconnect-mcp;
    }
    // {
      # Off in the chat until turned on in Settings, where its server and
      # API key are set (or in Nix: the ai.immich settings).
      immich.command = lib.getExe pkgs.customPkgs.immich-photo-manager;
    }
    # Jellyfin (jellyfinMcp.enable), off in the chat until set up in
    # Settings (server, a sign-in or an admin's API key, the player's login)
    # or in Nix (ai.jellyfin).
    // lib.optionalAttrs jellyfinOn {
      jellyfin.command = lib.getExe pkgs.customPkgs.jellyfin-mcp;
    }
    # Seerr (seerrMcp.enable), off in the chat until set up in Settings
    # (server, then your browser's login or an admin's API key) or in Nix
    # (ai.seerr).
    // lib.optionalAttrs seerrOn {
      seerr.command = lib.getExe pkgs.customPkgs.seerr-mcp;
    };

  # The Jellyfin player of this computer: jellyfin-mpv-shim, a cast target
  # (the server, the phone app or jellyfin-mcp send it what to play) that
  # plays in the user's own mpv (mpv_ext + mpv_ext_no_ovr: the same mpv.conf,
  # scripts and keys), fullscreen, without its own window or tray. It keeps
  # progress, marks watched and goes on to the next episode itself. These
  # keys are merged into its conf.json on each activation (it rewrites the
  # file, so it stays a real one), the others are its own.
  shim = pkgs.jellyfin-mpv-shim;
  shimDir = "${config.xdg.configHome}/jellyfin-mpv-shim";
  mpvExe =
    if config.programs.mpv.enable then
      lib.getExe config.programs.mpv.finalPackage
    else
      lib.getExe pkgs.mpv;
  shimSettings = {
    player_name = "${if os != null then hostName else "nixbook"} mpv";
    mpv_ext = true;
    mpv_ext_path = mpvExe;
    mpv_ext_no_ovr = true;
    mpv_ext_start = true;
    fullscreen = true;
    # Direct play: jellyfin-mpv-shim's 10 Mbit/s for "remote" servers (any
    # not on a private address) made the server transcode most files.
    remote_kbps =
      if cfg.jellyfinMcp.player.maxBitrateMbps == null then
        2147483
      else
        cfg.jellyfinMcp.player.maxBitrateMbps * 1000;
    # The user's own mpv and its controls only (modernx, thumbfast from
    # desktopApps' mpvConfig): "custom" loads none of the shim's on-screen
    # controls and turns mpv's built-in OSC off, where its default (with no
    # GUI: its copy of mpv's OSC) drew over modernx. Its own thumbfast
    # (Jellyfin's seek previews) would answer modernx beside the user's, and
    # its mouse.lua only serves the shim's own menu.
    osc_style = "custom";
    thumbnail_enable = false;
    menu_mouse = false;
    enable_gui = false;
    check_updates = false;
    notify_updates = "disabled";
    discord_presence = false;
  };
  # Started only once it is signed in (Settings > Desktop agents > Jellyfin,
  # `jellyfin-mcp shim-login`): without a login it would ask for a server on
  # its terminal and exit, again and again.
  shimSignedIn = pkgs.writeShellScript "jellyfin-mpv-shim-signed-in" ''
    exec ${lib.getExe pkgs.jq} -e '[.users[]?.credentials[]? | select(.AccessToken)] | length > 0' \
      "${shimDir}/users.json" >/dev/null 2>&1
  '';

  # What this machine's Nix configuration sets up, for the Intelligence tab's
  # system prompt: the assistant can then answer "how do I change X" with the
  # right module, profile file and deploy command. Built from the evaluated
  # configuration, so it follows every switch.
  context = ''
    ## This machine (generated from its Nix configuration)
    You are also this user's assistant for their NixOS setup. It is fully
    declarative: the "nixbook" repository (git@github.com:didactiklabs/nixbook,
    revision in /etc/nixos/version) builds every machine. When asked to change
    something, prefer the Nix change in the right file, applied with
    `colmena apply-local --sudo switch` from the repository: imperative
    changes (nix-env, editing /etc…) to things the configuration manages are
    undone by the next switch.

    - Host `${hostName}`${
      lib.optionalString (os != null)
        ", NixOS ${os.system.nixos.release}, kernel ${os.boot.kernelPackages.kernel.version}, ${pkgs.stdenv.hostPlatform.system}${
          lib.optionalString (os.time.timeZone != null) ", time zone ${os.time.timeZone}"
        }"
    }; user `${user}`
    - Machine profile: `profiles/${hostName}/default.nix` (system) and
      `profiles/${hostName}/${user}/default.nix` (this user's Home Manager
      settings: which modules are enabled and their options)
    - System modules live in `nixosModules/`, user modules in
      `homeManagerModules/`, custom packages in `customPkgs/`; keyboard
      shortcuts are documented in `KEYBINDS.md`
    - Enabled nixbook NixOS modules (`customNixOSModules.<name>.enable`): ${lib.concatStringsSep ", " osModules}
    - Enabled nixbook Home Manager modules (`customHomeManagerModules.<name>.enable`): ${lib.concatStringsSep ", " hmModules}
    ${lib.optionalString niriEnabled "- Compositor: niri (homeManagerModules/niri/niriConfig.nix; its keybinds are listed below)"}

    ## Desktop shell: nixbook-shell
    The bar, dock, sidebars, launcher, notifications, lock screen and desktop
    widgets are nixbook-shell, a Quickshell (QML) shell packaged in
    `nixbook-shell/` (source in `src/`, Home Manager module
    `programs.nixbook-shell` in `hm-module.nix`) and configured by
    `customHomeManagerModules.nixbookShellConfig`
    (`homeManagerModules/nixbookShellConfig.nix`). Its settings live in
    `~/.config/nixbook-shell/config.json` and are edited from its Settings
    window (Mod+Escape, or "Shell settings" in the launcher). Settings set in
    Nix (shared ones in `homeManagerModules/nixbookShellConfig/settings.nix`,
    per machine in `nixbookShellConfig.settings` of the user profile) are
    locked in that window; everything else is editable there.
    `nixbook-shell config diff` prints the settings changed from the menu as
    Nix lines, `nixbook-shell ipc call <target> <function>` drives panels.

    Settings set in Nix on this machine:
    ${config.programs.nixbook-shell.assistant.pinnedLines}

    ## Packages installed for this user (Home Manager)
    ${lib.concatStringsSep ", " (names config.home.packages)}
    ${lib.optionalString (os != null) ''

      ## System packages (NixOS)
      ${lib.concatStringsSep ", " (names os.environment.systemPackages)}
    ''}
  '';
in
{
  imports = [
    ../nixbook-shell/hm-module.nix
    # Profiles set the shell's settings as nixbookShellConfig.settings.
    (lib.mkAliasOptionModule
      [ "customHomeManagerModules" "nixbookShellConfig" "settings" ]
      [ "programs" "nixbook-shell" "settings" ]
    )
  ];

  options.customHomeManagerModules.nixbookShellConfig.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Whether to enable nixbook-shell, nixbook's Quickshell (QML) desktop shell
      (`programs.nixbook-shell`, packaged in nixbook-shell/), with the settings
      shared by every nixbook machine (nixbookShellConfig/settings.nix, as
      defaults a profile's `nixbookShellConfig.settings` override key by key).

      This is an alternative to DankMaterialShell (`dmsConfig`) — the two are
      mutually exclusive, since both draw a top bar, own the lock screen and
      register overlapping layer-shell surfaces. Flip `dmsConfig.enable` off
      when turning this on.

      The shell runs as the `nixbook-shell` user service, bound to
      `graphical-session.target`. Works under niri and Hyprland; under niri
      every panel is driven through `nixbook-shell ipc call <target> <function>`
      keybinds (homeManagerModules/niri/niriConfig.nix, KEYBINDS.md).
    '';
  };

  options.customHomeManagerModules.nixbookShellConfig.selfImprove.enable = lib.mkEnableOption ''
    the desktop agent fixing nixbook itself on this machine
    (programs.nixbook-shell.selfImprove.enable): fixes and polish, and apart
    the features asked for (never merged on their own), as pull requests
    made with a GitHub token set in Settings > Desktop agents. Only machines
    whose profile turns it on have it'';

  options.customHomeManagerModules.nixbookShellConfig.zenAgent.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Whether the desktop agents can use Zen through the page itself
      (nixbook-desktop-mcp's `page_*` tools: tabs, reading pages, clicking,
      typing, forms), without the mouse or keyboard, in background tabs and
      other workspaces, while you keep working. With `zenBrowserConfig`:
      force-installs nixbook-shell's Zen extension (unsigned:
      `xpinstall.signatures.required` is turned off in the profile) and its
      native messaging host. Private windows, password fields, the Banking
      container and password manager / payment sites are off limits
      (desktop-mcp's `browser` settings).
    '';
  };

  options.customHomeManagerModules.nixbookShellConfig.electronAccessibility = lib.mkOption {
    type = lib.types.bool;
    default = config.programs.nixbook-shell.desktopMcp.browserAccessibility;
    defaultText = lib.literalExpression "config.programs.nixbook-shell.desktopMcp.browserAccessibility";
    description = ''
      Whether the Chromium/Electron apps nixbook installs (Vesktop with
      desktopApps; the profiles wrap their own Slack and YouTube Music) start
      with their accessibility tree on (`--force-renderer-accessibility`,
      lib/electronA11y.nix), so the desktop agents read and act on them
      through the app itself (desktop-mcp's ui_read/ui_act), in any window and
      on any workspace, without the pointer. The session's
      ACCESSIBILITY_ENABLED alone leaves their pages empty. It costs those
      apps some CPU and memory. Only where nixbook-shell is enabled.
    '';
  };

  # What desktopApps and the profiles wrap their Electron apps with:
  # `electronA11y pkg bin` is, where nixbook-shell runs, the app started
  # through nixbook-electron-app when electronBridge lists its binary, else
  # with its accessibility tree on (electronAccessibility); the app unchanged
  # elsewhere (lib/electronA11y.nix).
  options.customHomeManagerModules.nixbookShellConfig.electronA11y = lib.mkOption {
    type = lib.types.functionTo (lib.types.functionTo lib.types.package);
    internal = true;
    readOnly = true;
    default = import ../lib/electronA11y.nix { inherit pkgs config; };
    defaultText = lib.literalExpression "pkg: bin: (lib/electronA11y.nix) where nixbook-shell is on, else pkg";
    description = "`pkg: bin:` the Electron app for the desktop agents where nixbook-shell runs.";
  };

  options.customHomeManagerModules.nixbookShellConfig.electronBridge = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether the Electron apps of `apps` that nixbook wraps (Vesktop with
        desktopApps; the profiles' own, e.g. Slack, YouTube Music and Actual
        Budget) start through nixbook-shell's bridge (`nixbook-electron-app`,
        lib/electronA11y.nix): the app's DevTools protocol on a private pipe
        only the launcher holds, behind a socket only you can reach, so the
        desktop agents read and use its pages like Zen's tabs (desktop-mcp's
        `page_*` tools; Discord also through its own client, the `discord`
        tool: find, read, send, react), without the mouse or keyboard, its
        window in the background. Password managers are never bridged.
        Agents sending or reacting are always asked first. Automating your own
        account may break the app's terms (Discord's and Slack's forbid
        self-bots). An app started without the bridge (already running when
        this is first deployed, or started some other way) is caught by the
        `nixbook-electron-watch` user service: started less than 60 s ago, it
        is restarted through the bridge silently; otherwise you get a
        notification with "Restart with bridge" — an app in use or in a call
        is never closed on its own.
      '';
    };
    apps = lib.mkOption {
      type = lib.types.attrsOf (lib.types.strMatching "[a-z0-9][a-z0-9-]{0,31}");
      default = {
        vesktop = "discord";
        slack = "slack";
        pear-desktop = "youtube-music";
        actual-budget = "actual";
      };
      description = ''
        The apps bridged, by the name of the binary nixbook wraps → the
        name agents know the app by (its target in `page_list`; `discord`
        has its own operations). Only the ones a machine installs through
        lib/electronA11y.nix are started so.
      '';
    };
  };

  options.customHomeManagerModules.nixbookShellConfig.linkedinMcp.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Whether to offer the nixbook-shell AI chat (Claude in the side panel, and
      nothing else: not your own Claude Code or other agents) LinkedIn, through
      [linkedin-mcp-server](https://github.com/stickerdaniel/linkedin-mcp-server)
      (`customPkgs.linkedin-mcp-server`): profiles, people and company
      search, messages, jobs, the feed, on your own account in a browser
      session of its own (`~/.linkedin-mcp`, signed in from Settings > Desktop
      agents or `mcp-server-linkedin --login`). Installed, but off in the chat
      until you turn it on in Settings > Desktop agents > Apps it can use.
      LinkedIn's terms forbid automated access and it may restrict accounts
      using it. Pulls in Chromium: `false` leaves it out entirely.
    '';
  };

  options.customHomeManagerModules.nixbookShellConfig.seerrMcp.enable = lib.mkOption {
    type = lib.types.nullOr lib.types.bool;
    default = null;
    defaultText = lib.literalMD "`null`: follows `jellyfinMcp.enable`";
    description = ''
      Whether to offer the nixbook-shell AI chat (Claude in the side panel and
      its speech bubble) the user's Seerr (Overseerr / Jellyseerr) through
      `customPkgs.seerr-mcp`: search films and series and see what is
      available or on its way, request them (a film, a series' seasons),
      follow, cancel, approve or decline requests, trending and upcoming.
      Off in the chat until set up in Settings > Desktop agents > Apps it can
      use: the server, then your own login (sign in to Seerr in Zen, Firefox
      or Chrome as usual, OpenID Connect included, and Settings takes only
      Seerr's session cookie into the keyring: Claude acts as you, no admin
      key), or an admin's API key with who requests go out as (`ai.seerr`).
    '';
  };
  options.customHomeManagerModules.nixbookShellConfig.jellyfinMcp = {
    # null: decided here (Moonfin installed) — a default reading
    # home.packages couldn't be evaluated by docs/generate-docs.nix.
    enable = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      defaultText = lib.literalMD "`null`: on when Moonfin (`customPkgs.moonfin`) is in `home.packages`";
      description = ''
        Whether to offer the nixbook-shell AI chat (Claude in the side panel
        and its speech bubble) the user's Jellyfin library through
        `customPkgs.jellyfin-mcp`: search, details, continue watching, next
        up, what plays where; play and control it, mark watched, favourites,
        playlists. Also the bubble's instant "play <title> season N episode
        M" (no model). Off in the chat until set up in Settings > Desktop
        agents > Apps it can use (the server, then a sign-in with your own
        Jellyfin account — no admin needed — or an admin's API key; or the
        `ai.jellyfin` settings).
      '';
    };
    player.enable = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      defaultText = lib.literalMD "`null`: follows `jellyfinMcp.enable`";
      description = ''
        Whether this computer is a Jellyfin player: jellyfin-mpv-shim as the
        `jellyfin-mpv-shim` user service, playing in your own mpv
        (fullscreen, your mpv config), castable from Jellyfin's apps, and
        where jellyfin-mcp plays by default. It saves progress, marks watched
        and plays the next episode itself. It starts once signed in, from
        Settings > Desktop agents > Apps it can use ("Connect the player").
      '';
    };
    player.maxBitrateMbps = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      example = 20;
      description = ''
        The most the player streams from a server it doesn't see on the
        local network (in Mbit/s); more is transcoded by the server.
        `null`: no limit, so it plays the files as they are (mpv plays
        almost anything). jellyfin-mpv-shim's own default is 10, which
        transcodes most 1080p and every 4K file from a server behind a
        public address, a reverse proxy or a VPN (100.64.0.0/10 isn't
        "local" to it). The server's own limits (Dashboard > Users > the
        user's "Internet streaming bitrate limit", Dashboard > Playback >
        Streaming) still apply.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          !lib.any (
            n:
            builtins.match ".*(keepass|bitwarden|1password|enpass|proton-?pass|lastpass|dashlane|keeper|nordpass|authenticator).*" n
            != null
          ) (lib.attrNames cfg.electronBridge.apps ++ lib.attrValues cfg.electronBridge.apps);
        message = ''
          nixbookShellConfig.electronBridge.apps lists a password manager: they
          are never bridged to the desktop agents.
        '';
      }
      {
        assertion =
          !lib.hasPrefix builtins.storeDir (
            toString (lib.attrByPath [ "ai" "jellyfin" "apiKeyFile" ] "" config.programs.nixbook-shell.settings)
          );
        message = ''
          nixbookShellConfig.settings.ai.jellyfin.apiKeyFile is in the Nix store,
          readable by every user: point it at a file outside it.
        '';
      }
      {
        assertion =
          !lib.hasPrefix builtins.storeDir (
            toString (lib.attrByPath [ "ai" "immich" "apiKeyFile" ] "" config.programs.nixbook-shell.settings)
          );
        message = ''
          nixbookShellConfig.settings.ai.immich.apiKeyFile is in the Nix store,
          readable by every user: point it at a file outside it.
        '';
      }
      {
        assertion =
          !lib.hasPrefix builtins.storeDir (
            toString (lib.attrByPath [ "ai" "seerr" "apiKeyFile" ] "" config.programs.nixbook-shell.settings)
          );
        message = ''
          nixbookShellConfig.settings.ai.seerr.apiKeyFile is in the Nix store,
          readable by every user: point it at a file outside it.
        '';
      }
      {
        assertion = !config.customHomeManagerModules.dmsConfig.enable;
        message = ''
          customHomeManagerModules.nixbookShellConfig and customHomeManagerModules.dmsConfig
          cannot both be enabled: both shells draw a top bar, a lock screen and
          overlapping layer-shell surfaces. Pick one.
        '';
      }
    ];

    systemd.user.services.jellyfin-mpv-shim = lib.mkIf jellyfinPlayerOn {
      Unit = {
        Description = "Jellyfin MPV Shim: this computer as a Jellyfin player (mpv)";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
        X-Restart-Triggers = [ (builtins.toJSON shimSettings) ];
      };
      Service = {
        ExecCondition = shimSignedIn;
        ExecStart = "${lib.getExe shim} --no-gui";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
    home.activation.jellyfinMpvShimConfig = lib.mkIf jellyfinPlayerOn (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        conf="${shimDir}/conf.json"
        live='{}'
        if [ -s "$conf" ] && ! live=$(${lib.getExe pkgs.jq} -c . "$conf" 2>/dev/null); then
          warnEcho "$conf isn't valid JSON: left alone (jellyfin-mpv-shim's settings not applied)"
          live=""
        fi
        if [ -n "$live" ] && [[ ! -v DRY_RUN ]]; then
          uuid=$(${lib.getExe pkgs.jq} -r '.client_uuid // empty' <<<"$live")
          [ -n "$uuid" ] || uuid=$(cat /proc/sys/kernel/random/uuid)
          new=$(${lib.getExe pkgs.jq} -c --argjson pinned ${lib.escapeShellArg (builtins.toJSON shimSettings)} \
            --arg uuid "$uuid" '. * $pinned | .client_uuid = $uuid' <<<"$live")
          if [ "$new" != "$live" ]; then
            mkdir -p "${shimDir}"
            ${lib.getExe pkgs.jq} --sort-keys . <<<"$new" >"$conf.hm-tmp" && mv "$conf.hm-tmp" "$conf"
          fi
        fi
      ''
    );

    # What nixbook defines itself, for the fixer: the user units of its own
    # modules (the system ones: /etc/nixbook/owned-units.json,
    # nixosModules/ownedUnits.nix) and its own packages. Errors from
    # anything else are "not nixbook's", never sent to it unasked.
    xdg.configFile."nixbook-shell/owned.json" = lib.mkIf cfg.selfImprove.enable {
      text =
        let
          ours = import ../lib/ownedUnits.nix { inherit lib; } (toString ../.);
        in
        builtins.toJSON {
          userServices = ours options.systemd.user.services.definitionsWithLocations;
          userTimers = ours options.systemd.user.timers.definitionsWithLocations;
          packages = lib.attrNames pkgs.customPkgs ++ [
            "nixbook-shell"
            "quickshell"
          ];
        };
    };

    programs.nixbook-shell = {
      enable = true;
      # The repository's quickshell pin, shared with dmsConfig.nix so the two
      # shells never disagree on the QML runtime.
      package =
        (import ../nixbook-shell {
          inherit pkgs;
          quickshellSrc = sources.quickshell;
          # The VPN CLIs of the VpnStatus widget, only where the machine runs
          # that VPN (standalone Home Manager: both).
          withTailscale = os == null || (os.services.tailscale.enable or false);
          withNetbird = os == null || (os.services.netbird.enable or false);
        }).package;
      # Shared settings, as defaults so a profile's `settings` win key by key.
      settings = lib.mapAttrsRecursive (_: lib.mkDefault) (import ./nixbookShellConfig/settings.nix);

      # Qt apps can follow the palette the shell shows (the wallpaper's or the
      # theme variant's) instead of stylix's (stylixConfig.nix turns its qt and
      # zen-browser targets off for this). Which apps do (Qt/KDE, Vesktop,
      # Zen) is switched in the shell: Settings > Appearance > Color
      # generation > Apps.
      appTheming.qt.enable = true;

      selfImprove.enable = cfg.selfImprove.enable;

      # The bridged Electron apps installed (lib/electronA11y.nix, in
      # desktopApps or a profile), watched by nixbook-electron-watch: one
      # running without its bridge is restarted through it or you are asked.
      electronBridge.apps = map (p: p.nixbookElectronBridge) (
        lib.filter (p: p ? nixbookElectronBridge) config.home.packages
      );

      assistant = {
        inherit context;
        niriConfig = if niriEnabled then (config.programs.niri.finalConfig or "") else "";
        # Where pear-desktop or Spotify is installed, the chat can also play and
        # control it (YouTube Music through the app's API Server plugin, turned
        # on in the app; Spotify through MPRIS, and its Web API after the
        # server's `login`); LinkedIn (linkedinMcp.enable), off in the chat
        # until turned on in Settings, and Immich and Jellyfin
        # (jellyfinMcp.enable), set up there. Added to the
        # option's default servers, not instead of them.
        mcpServers = lib.mkIf (extraMcpServers != { }) (
          options.programs.nixbook-shell.assistant.mcpServers.default // extraMcpServers
        );
        modules = {
          all =
            lib.optionals (os != null) (declared (os.customNixOSModules or { }))
            ++ declared (config.customHomeManagerModules or { });
          enabled = osModules ++ hmModules;
        };
        # nixbook's own way of applying and updating (the other how-tos keep
        # nixbook-shell's generic NixOS answers).
        howTo = {
          apply = {
            en = "To apply a configuration change, run `colmena apply-local --sudo switch` from the nixbook repository.";
            fr = "Pour appliquer une modification de la configuration, lancez `colmena apply-local --sudo switch` depuis le dépôt nixbook.";
            de = "Um eine Konfigurationsänderung anzuwenden, führe `colmena apply-local --sudo switch` im nixbook-Repository aus.";
            vi = "Để áp dụng thay đổi cấu hình, chạy `colmena apply-local --sudo switch` trong kho nixbook.";
          };
          update = lib.mkIf (os != null && (os.customNixOSModules.tools.enable or false)) {
            en = "To update the system, run `osupdate`: it applies the latest nixbook main branch (git@github.com:didactiklabs/nixbook).";
            fr = "Pour mettre à jour le système, lancez `osupdate` : il applique la dernière version de la branche main de nixbook (git@github.com:didactiklabs/nixbook).";
            de = "Um das System zu aktualisieren, führe `osupdate` aus: es wendet den neuesten Stand des nixbook-Branches main an (git@github.com:didactiklabs/nixbook).";
            vi = "Để cập nhật hệ thống, chạy `osupdate`: nó áp dụng bản mới nhất của nhánh main của nixbook (git@github.com:didactiklabs/nixbook).";
          };
        };
        coreFacts = [
          {
            en = "System settings (NixOS modules and their options) are changed in profiles/${hostName}/default.nix.";
            fr = "Les réglages système (modules NixOS et leurs options) se changent dans profiles/${hostName}/default.nix.";
            de = "Systemeinstellungen (NixOS-Module und ihre Optionen) werden in profiles/${hostName}/default.nix geändert.";
            vi = "Thiết lập hệ thống (module NixOS và tùy chọn) được đổi trong profiles/${hostName}/default.nix.";
          }
          {
            en = "This user's Home Manager modules and their options are changed in profiles/${hostName}/${user}/default.nix.";
            fr = "Les modules Home Manager de cet utilisateur et leurs options se changent dans profiles/${hostName}/${user}/default.nix.";
            de = "Die Home-Manager-Module dieses Benutzers und ihre Optionen werden in profiles/${hostName}/${user}/default.nix geändert.";
            vi = "Module Home Manager của người dùng này và tùy chọn được đổi trong profiles/${hostName}/${user}/default.nix.";
          }
          {
            en = "Shell settings (bar, dock, widgets, notifications, theme) set in Nix are in homeManagerModules/nixbookShellConfig/settings.nix (shared) or nixbookShellConfig.settings in the user profile; the others are changed in the shell's Settings window.";
            fr = "Les réglages du shell (barre, dock, widgets, notifications, thème) définis dans Nix sont dans homeManagerModules/nixbookShellConfig/settings.nix (communs) ou nixbookShellConfig.settings dans le profil utilisateur ; les autres se changent dans la fenêtre des paramètres du shell.";
            de = "In Nix gesetzte Shell-Einstellungen (Leiste, Dock, Widgets, Benachrichtigungen, Design) stehen in homeManagerModules/nixbookShellConfig/settings.nix (gemeinsam) oder nixbookShellConfig.settings im Benutzerprofil; die übrigen werden im Einstellungsfenster der Shell geändert.";
            vi = "Thiết lập shell (thanh, dock, widget, thông báo, giao diện) đặt trong Nix nằm ở homeManagerModules/nixbookShellConfig/settings.nix (dùng chung) hoặc nixbookShellConfig.settings trong hồ sơ người dùng; các thiết lập khác đổi trong cửa sổ cài đặt của shell.";
          }
          {
            en = "The keyboard shortcuts are documented in KEYBINDS.md in the nixbook repository.";
            fr = "Les raccourcis clavier sont documentés dans KEYBINDS.md dans le dépôt nixbook.";
            de = "Die Tastenkürzel sind in KEYBINDS.md im nixbook-Repository dokumentiert.";
            vi = "Các phím tắt được ghi trong KEYBINDS.md của kho nixbook.";
          }
        ];
      };
    };
  };
}
