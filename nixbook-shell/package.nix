{
  pkgs,
  quickshellSrc,
  dankcalendarSrc,
  flakeCompatSrc,
}:
# The `nixbook-shell` launcher: `nixbook-shell` starts the shell,
# `nixbook-shell ipc call <target> <fn>` drives it, `nixbook-shell splash` shows
# the loading screen until it is up, `nixbook-shell config …` relates the
# live settings to Nix. `passthru` carries the pieces the Home Manager module
# (hm-module.nix) needs. See README.md for the layout of this directory.
let
  inherit (pkgs) lib;

  shell = import ./qml.nix { inherit pkgs; };
  quickshell = import ./quickshell.nix { inherit pkgs quickshellSrc; };
  dankcalendar = import ./dankcalendar.nix { inherit pkgs dankcalendarSrc flakeCompatSrc; };
  settingsLib = import ./lib.nix { inherit lib; };
  fonts = import ./fonts.nix { inherit pkgs; };
  inherit (shell.passthru) configName;

  # Claude usage reader for the AnthropicUsage bar widget (OpenCode OAuth).
  anthropicUsage = pkgs.writeShellScriptBin "anthropic-usage" (
    builtins.readFile ./scripts/anthropic-usage.sh
  );

  # Desktop control for AI agents (scripts/desktop-mcp.py): an MCP server
  # (`nixbook-desktop-mcp`, also `nixbook-shell mcp`) and the command line
  # the shell's AI chat calls, with the tools it drives on its PATH.
  desktopMcp = pkgs.writeShellScriptBin "nixbook-desktop-mcp" ''
    export PATH="${
      lib.makeBinPath (
        with pkgs;
        [
          niri
          grim
          wtype
          ydotool
          wl-clipboard
          libnotify
          imagemagick # scales window captures down
          tesseract # read_screen
          systemd # systemctl: starts the agent desktop (agentDesktop)
        ]
      )
    }:$PATH"
    export NIXBOOK_DESKTOP_MCP_QS="${quickshell}/bin/qs"
    export NIXBOOK_DESKTOP_MCP_QS_CONFIG="${configName}"
    # The ui tools read apps' accessibility trees through at-spi2-core's
    # GObject bindings.
    export GI_TYPELIB_PATH="${
      lib.makeSearchPath "lib/girepository-1.0" (
        map (p: p.out) [
          pkgs.at-spi2-core
          pkgs.glib
          pkgs.gobject-introspection
        ]
      )
    }''${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
    exec ${
      pkgs.python3.withPackages (ps: [ ps.pygobject3 ])
    }/bin/python3 ${./scripts/desktop-mcp.py} "$@"
  '';

  # A desktop of their own for AI agents (scripts/agent-desktop.sh): a nested
  # niri that `nixbook-desktop-mcp desktop agent` points the agents' tools
  # at, run by the `nixbook-agent-desktop` user service.
  # Its niri (niri-winit-agent-window.patch) drops the input of its window
  # (NIRI_WINIT_IGNORE_INPUT): the user can move, resize and close the window
  # but not click or type into it; and names it (NIRI_WINIT_TITLE,
  # NIRI_WINIT_APP_ID) like an app; and keeps the windows its rules open
  # fullscreen so, whatever the app asks (NIRI_KEEP_FULLSCREEN). The agent's
  # only: the user's niri stays the cached nixpkgs one, this one builds
  # locally (tests off).
  agentNiri = pkgs.niri.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./niri-winit-agent-window.patch ];
    doCheck = false;
  });
  # A restricted socket on the user's compositor (security-context-v1) for the
  # agent desktop's niri: no screen capture, input or window list of the
  # user's desktop through it (scripts/wayland-security-context.py).
  securityContext = pkgs.writeShellScriptBin "nixbook-wayland-security-context" ''
    exec ${pkgs.python3}/bin/python3 ${./scripts/wayland-security-context.py} "$@"
  '';
  agentDesktop = pkgs.writeShellScriptBin "nixbook-agent-desktop" ''
    export PATH="${
      lib.makeBinPath (
        with pkgs;
        [
          agentNiri
          dbus # dbus-run-session: the agent apps' own session bus
          xwayland-satellite # X11 apps on the agent desktop, not the user's
          bubblewrap # the sandbox: none of the user's files, sockets or processes
          passt # pasta: the sandbox's own network (ai.agentDesktop.privateNetwork)
          securityContext # its restricted connection to the user's desktop
          libnotify # notify-send: why it didn't start
          jq # the folders the user lets agents read (shell config)
          findutils
          coreutils
        ]
      )
    }:$PATH"
    exec ${pkgs.bash}/bin/bash ${./scripts/agent-desktop.sh} "$@"
  '';

  # Upstream probes ~40 tools with `command -v` and shells out to them from QML
  # `Process` blocks. Rather than patching every call site we inject them into
  # the shell's PATH; children inherit it.
  runtimeDeps =
    (with pkgs; [
      bash
      coreutils
      findutils
      gawk
      gnugrep
      gnused
      procps # pgrep
      psmisc # killall
      sysvtools # pidof

      jq
      curl
      gitMinimal # `git ls-remote` for the update check (services/UpdateState.qml)
      wget
      libnotify # notify-send
      glib # gsettings
      xdg-utils # xdg-open
      util-linux

      imagemagick # magick / convert / identify
      matugen
      ffmpeg
      mpvpaper

      wl-clipboard
      cliphist
      grim
      slurp
      wf-recorder
      ydotool
      wtype # desktop-mcp keyboard input (virtual keyboard, no uinput)
      tesseract # region OCR

      playerctl
      pulseaudio # pactl
      wireplumber # wpctl
      brightnessctl
      cava
      ddcutil
      networkmanager # nmcli
      translate-shell # trans
      kdePackages.kdialog

      songrec # Shazam CLI behind scripts/musicRecognition + its quick toggle
      easyeffects # EasyEffects quick toggle and the shell's EQ panel
      lm_sensors # `sensors` — temperatures in ResourceUsage
      file # MIME sniffing for chat attachments and directory icons
      zip # settings preset export/import (scripts/presets.sh)

      tailscale # VpnStatus bar widget — `tailscale status/switch/set`
      netbird # VpnStatus bar widget — `netbird status/up/down/profile`

      niri
      btop # task manager (Config.options.apps.taskManager)
    ])
    ++ [
      quickshell # `qs` — the shell re-invokes itself for sub-windows
      dankcalendar # `dcal` — calendar events and tasks (CalendarEvents, Todo)
      shell.passthru.pythonEnv
      anthropicUsage # `anthropic-usage` — AnthropicUsage bar widget
      desktopMcp # `nixbook-desktop-mcp` — desktop tools of the AI chat
    ];

  # QML modules the shell imports that quickshell itself is not built against,
  # so they are absent from its wrapper's QML import path. Without these the
  # shell dies at startup with "module <x> is not installed":
  #   Qt5Compat.GraphicalEffects -> qt5compat          (ReloadPopup and friends)
  #   QtPositioning              -> qtpositioning      (weather / auto-location)
  #   org.kde.syntaxhighlighting -> syntax-highlighting (AI chat code blocks)
  #   org.kde.kirigami           -> kirigami           (common/widgets/AppIcon)
  # Everything else it imports (QtQuick.*, QtQml.*, Qt.labs.*, QtCore) already
  # comes from qtdeclarative via quickshell.
  #
  # nixpkgs' Qt6 uses a patched qtbase that reads NIXPKGS_QT6_QML_IMPORT_PATH,
  # and quickshell's wrapper extends it with `--prefix`, so exporting it here
  # is additive rather than destructive.
  qmlImportPath = lib.makeSearchPath "lib/qt-6/qml" [
    pkgs.qt6.qt5compat
    pkgs.qt6.qtpositioning
    pkgs.kdePackages.syntax-highlighting
    # `kdePackages.kirigami` is a Qt app wrapper with no lib/ output; the QML
    # module only exists in the unwrapped derivation.
    pkgs.kdePackages.kirigami.unwrapped
  ];

  # `nixbook-shell config …` (scripts/config-tool.sh). Reads the settings set in Nix
  # from ~/.config/nixbook-shell/nix-pinned-values.json at run time, so the
  # CLI doesn't depend on the module's configuration.
  # jq resolves `include "config-merge"` by file name in the -L directory.
  mergeLib = pkgs.writeTextDir "lib/config-merge.jq" (builtins.readFile ./scripts/config-merge.jq);
  configTool = pkgs.writeShellScript "nixbook-shell-config" ''
    export PATH="${
      lib.makeBinPath [
        pkgs.jq
        pkgs.coreutils
      ]
    }:$PATH"
    export NIXBOOK_SHELL_MERGE_JQ="${mergeLib}/lib/config-merge.jq"
    export NIXBOOK_SHELL_BUILTIN="${./builtin-defaults.json}"
    export NIXBOOK_SHELL_LIVE_KEYS="${pkgs.writeText "nixbook-shell-live-keys.json" (builtins.toJSON settingsLib.skippedKeys)}"
    # `config builtin`: run the shell's Config singleton alone against an empty
    # config dir to get its built-in defaults.
    export NIXBOOK_SHELL_SHELL="${shell}"
    export NIXBOOK_SHELL_QS="${quickshell}/bin/qs"
    export NIXBOOK_SHELL_QML_PATH="${qmlImportPath}"
    exec ${pkgs.bash}/bin/bash ${./scripts/config-tool.sh} "$@"
  '';

  # cliphist store daemon. Nothing else in this config runs one, so without it
  # the shell's clipboard history (Mod+Q) is permanently empty.
  cliphistWatch = pkgs.writeShellScript "nixbook-shell-cliphist-watch" ''
    ${pkgs.wl-clipboard}/bin/wl-paste --type text --watch ${pkgs.cliphist}/bin/cliphist store &
    ${pkgs.wl-clipboard}/bin/wl-paste --type image --watch ${pkgs.cliphist}/bin/cliphist store &
    wait
  '';

  # Single entry point: keybinds and the systemd unit both go through this so
  # the runtime PATH and QML import path are always correct.
  launcher = pkgs.writeShellScriptBin "nixbook-shell" ''
    # `nixbook-shell config …`: how the live settings relate to the Nix module.
    if [ "''${1:-}" = "config" ]; then
      shift
      exec ${configTool} "$@"
    fi
    # `nixbook-shell mcp …`: the desktop control MCP server (desktopMcp).
    if [ "''${1:-}" = "mcp" ]; then
      shift
      exec ${lib.getExe desktopMcp} "$@"
    fi
    export PATH="${lib.makeBinPath runtimeDeps}:$PATH"
    export NIXPKGS_QT6_QML_IMPORT_PATH="${qmlImportPath}''${NIXPKGS_QT6_QML_IMPORT_PATH:+:$NIXPKGS_QT6_QML_IMPORT_PATH}"
    # Quickshell resolves `image://icon/...` against this rather than the GTK
    # settings; without it half the tray/launcher icons fail to load. Override
    # it in the environment for another theme. Set here rather than in home.sessionVariables
    # so it also applies to the systemd unit without needing a re-login.
    export QS_ICON_THEME="''${QS_ICON_THEME:-Papirus-Dark}"
    # `nixbook-shell splash`: the loading screen shown while the shell starts
    # (src/earlySplash.qml, its own instance: quits once the shell's is up).
    if [ "''${1:-}" = "splash" ]; then
      shift
      exec ${quickshell}/bin/qs -p ${shell}/earlySplash.qml "$@"
    fi
    # `nixbook-shell greeter`: the login screen (src/greeter.qml), run by
    # greetd through the nixbook-shell.greeter NixOS module.
    if [ "''${1:-}" = "greeter" ]; then
      shift
      exec ${quickshell}/bin/qs -p ${shell}/greeter.qml "$@"
    fi
    exec ${quickshell}/bin/qs -c ${configName} "$@"
  '';
in
launcher.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    inherit
      shell
      quickshell
      dankcalendar
      configName
      settingsLib
      cliphistWatch
      desktopMcp
      agentDesktop
      securityContext
      fonts
      ;
  };
  meta = shell.meta // {
    mainProgram = "nixbook-shell";
  };
})
