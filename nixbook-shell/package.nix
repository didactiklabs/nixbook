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
      fonts
      ;
  };
  meta = shell.meta // {
    mainProgram = "nixbook-shell";
  };
})
