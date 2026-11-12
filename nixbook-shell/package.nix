{
  pkgs,
  quickshellSrc,
  # The Google Keep client for the notes' sync with Keep (an npins pin).
  gkeepapiSrc,
  # Dark Reader's library (an npins pin of its npm tarball): web pages in
  # the shell's colours, in Zen (zen/pages-theme.js).
  darkreaderSrc,
  # The VPN CLIs behind the VpnStatus bar widget (services/VpnState.qml probes
  # them with `command -v`, so the widget only shows the ones it finds). Off
  # where they are on the PATH anyway or not used, to keep them out of the
  # closure.
  withTailscale ? true,
  withNetbird ? true,
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
  accounts = import ./accounts.nix { inherit pkgs; };
  # The desktop agent's fixes to nixbook (`nixbook-improve`, services/SelfImprove.qml).
  improve = import ./improve.nix { inherit pkgs; };
  # The notes' sync with Google Keep (`nixbook-keep`, services/KeepSync.qml).
  keep = import ./keep.nix { inherit pkgs gkeepapiSrc; };
  # The mesh between people's desktops (`nixbook-mesh`, services/Mesh.qml).
  mesh = import ./mesh.nix { inherit pkgs; };
  # YouTube Music in the background (`nixbook-ytmusic`, services/YouTubeMusic.qml).
  ytmusic = import ./ytmusic.nix { inherit pkgs; };
  settingsLib = import ./lib.nix { inherit lib; };
  # wl-clipboard with a wl-copy that keeps text as text (wl-copy.nix).
  wlClipboard = import ./wl-copy.nix { inherit pkgs; };
  # The live wallpaper player, drawing at the output's own pixels on a
  # fractionally scaled output (patches/mpvpaper-fractional-scale.patch), and
  # started transparent until the shell has stacked its desktop above it
  # (patches/mpvpaper-hold.patch).
  mpvpaper = pkgs.mpvpaper.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ./patches/mpvpaper-fractional-scale.patch
      ./patches/mpvpaper-hold.patch
    ];
  });
  fonts = import ./fonts.nix { inherit pkgs; };
  inherit (shell.passthru) configName;

  # The update check (scripts/update-check.sh), run by the updates widget
  # through systemd-run: a user unit doesn't get the shell's PATH.
  updateCheck = pkgs.writeShellScriptBin "nixbook-update-check" ''
    export PATH=${
      lib.makeBinPath (
        with pkgs;
        [
          coreutils
          gawk
          gitMinimal
          openssh
          jq
          curl
        ]
      )
    }:$PATH
    exec ${pkgs.bash}/bin/bash ${./scripts/update-check.sh} "$@"
  '';

  # Echo cancellation and clearer voices in calls (scripts/echo-cancel.sh),
  # run by the `nixbook-echo-cancel` user unit (hm-module.nix,
  # services/EchoCancel.qml). LADSPA_PATH: swh's compressor (sc4) and
  # limiter, for its speech stages.
  echoCancel = pkgs.writeShellScriptBin "nixbook-echo-cancel" ''
    export LADSPA_PATH=${pkgs.ladspaPlugins}/lib/ladspa
    export PATH=${
      lib.makeBinPath (
        with pkgs;
        [
          coreutils
          gnused
          jq
          pipewire
          wireplumber
        ]
      )
    }:$PATH
    exec ${pkgs.bash}/bin/bash ${./scripts/echo-cancel.sh} "$@"
  '';

  # The battery's charge limit, read and set for the bar's battery panel
  # (scripts/charge-limit.sh, services/Battery.qml). systemctl comes from the
  # system: it must be the one that talks to the running systemd.
  chargeLimit = pkgs.writeShellScriptBin "nixbook-charge-limit" ''
    exec ${pkgs.bash}/bin/bash ${./scripts/charge-limit.sh} "$@"
  '';

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
          wlClipboard
          libnotify
          imagemagick # scales window captures down
          tesseract # read_screen
          systemd # systemctl: the user services it drives (habits…)
          pciutils # lspci: GPU names (system_info)
          playerctl # the music every player plays (usage habits: music taste)
          accounts # nixbook-accounts: the contacts tool
          improve # nixbook-improve: report_problem
          libarchive # bsdtar: `extract`, a download extracted from its bubble
          procps # pgrep: a watched process
          cliphist # find_anything: the clipboard history
          poppler-utils # pdftotext: find_anything reads PDFs' first pages
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
    # -P: not the script's directory on sys.path. That is /nix/store, which
    # the first import would list whole (tens of thousands of entries:
    # ~70 ms of each run, the shell's commands and every MCP server start).
    exec ${desktopMcpPython}/bin/python3 -P ${desktopMcpPyc} "$@"
  '';
  desktopMcpPython = pkgs.python3.withPackages (ps: [ ps.pygobject3 ]);
  # Its source is split by area (scripts/desktop-mcp/NN-area.py, which
  # scripts/desktop-mcp.py runs in order in one namespace): joined here into
  # the one file they were.
  desktopMcpSource = pkgs.runCommand "desktop-mcp.py" { } ''
    for part in $(LC_ALL=C ls ${./scripts/desktop-mcp}/*.py); do
      cat "$part" >>$out
    done
  '';
  # Precompiled: the shell runs it on every habit cue, memory lookup and agent
  # tool call, and a script run as __main__ is never cached (compiling its
  # 18k lines was ~160 ms of CPU per run). Tracebacks still show the source.
  desktopMcpPyc = pkgs.runCommand "desktop-mcp.pyc" { } ''
    ${desktopMcpPython}/bin/python3 -c 'import py_compile, sys; py_compile.compile(sys.argv[1], cfile=sys.argv[2], dfile=sys.argv[1], doraise=True, invalidation_mode=py_compile.PycInvalidationMode.UNCHECKED_HASH)' ${desktopMcpSource} $out
  '';

  # The desktop agents in Zen (nixbook-desktop-mcp's page_* tools): the
  # extension (zen/, unsigned: Zen doesn't require signing, the profile
  # turns the check off) force-installed by the browser's policies, and its
  # native messaging host, a bridge to a private Unix socket
  # ($XDG_RUNTIME_DIR/nixbook-zen/bridge.sock). nixbook's zenBrowserConfig
  # installs both (`passthru.zenAgent`).
  zenExtensionId = "desktop-agent@nixbook-shell";
  # Web pages in the shell's colours (zen/pages-theme.js): Dark Reader's
  # library (MIT), from its npm tarball.
  zenExtension = pkgs.runCommand "nixbook-zen-extension.xpi" { nativeBuildInputs = [ pkgs.zip ]; } ''
    cp ${./zen}/manifest.json ${./zen}/page.js ${./zen}/background.js ${./zen}/pages-theme.js .
    tar -xzf ${darkreaderSrc} package/darkreader.js package/LICENSE
    mv package/darkreader.js darkreader.js
    mv package/LICENSE darkreader-LICENSE
    zip -q -X -9 $out manifest.json page.js background.js pages-theme.js darkreader.js darkreader-LICENSE
  '';
  zenBridge = pkgs.writeShellScriptBin "nixbook-zen-bridge" ''
    exec ${pkgs.python3}/bin/python3 -I ${./scripts/zen-bridge.py} "$@"
  '';
  zenBridgeHost = pkgs.runCommand "nixbook-zen-bridge-host" { } ''
    mkdir -p $out/lib/mozilla/native-messaging-hosts
    cat > $out/lib/mozilla/native-messaging-hosts/nixbook_zen.json <<EOF
    {
      "name": "nixbook_zen",
      "description": "nixbook's desktop agents in the browser (nixbook-desktop-mcp)",
      "path": "${zenBridge}/bin/nixbook-zen-bridge",
      "type": "stdio",
      "allowed_extensions": ["${zenExtensionId}"]
    }
    EOF
  '';
  # The same page tools in Electron apps: `nixbook-electron-app APP -- BINARY
  # ARGS…` starts the app with its DevTools protocol on a private pipe and
  # serves its fixed operations on $XDG_RUNTIME_DIR/nixbook-electron/APP.sock
  # (scripts/electron-bridge.py; Zen's page code, zen/page.js, and an app's
  # own operations, electron/APP.js: discord, actual). nixbook's lib/electronA11y.nix
  # starts the apps it wraps through it (`passthru.electronBridge`).
  # Its watcher (`watch`) tells the user with notify-send, sees calls with
  # pactl and starts apps in a scope of their own with systemd-run.
  electronBridge = pkgs.writeShellScriptBin "nixbook-electron-app" ''
    export NIXBOOK_NOTIFY_SEND=${pkgs.libnotify}/bin/notify-send \
      NIXBOOK_PACTL=${pkgs.pulseaudio}/bin/pactl NIXBOOK_SYSTEMD_RUN=${pkgs.systemd}/bin/systemd-run
    exec ${pkgs.python3}/bin/python3 -I ${./scripts/electron-bridge.py} \
      --page-js ${./zen/page.js} --adapters ${./electron} "$@"
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
      wget
      libnotify # notify-send
      glib # gsettings
      xdg-utils # xdg-open
      util-linux

      imagemagick # magick / convert / identify
      matugen
      ffmpeg # ffplay: sounds pw-play can't decode
      pipewire # pw-play: sounds
      mpvpaper # the patched one above (a let binding wins over `with pkgs`)
      socat # live-wallpaper.sh: mpv's IPC socket (pause, swap in the copy)

      wlClipboard
      cliphist
      grim
      slurp
      wf-recorder
      ydotool
      wtype # desktop-mcp keyboard input (virtual keyboard, no uinput)
      tesseract # region OCR
      libqalculate # qalc: the launcher's maths (LauncherSearch's mathProc)
      poppler-utils # pdftotext/pdftoppm/pdfinfo: DAI reads PDFs (its Bash; read_document OCRs with tesseract)

      playerctl
      pulseaudio # pactl
      wireplumber # wpctl
      brightnessctl
      cava
      ddcutil
      networkmanager # nmcli
      translate-shell # trans
      kdePackages.kdialog

      easyeffects # EasyEffects quick toggle and the shell's EQ panel
      lm_sensors # `sensors` — temperatures in ResourceUsage
      file # MIME sniffing for chat attachments and directory icons
      zip # settings preset export/import (scripts/presets.sh)

      niri
      btop # task manager (Config.options.apps.taskManager)
    ])
    ++ lib.optional withTailscale pkgs.tailscale # VpnStatus bar widget — `tailscale status/switch/set`
    ++ lib.optional withNetbird pkgs.netbird # VpnStatus bar widget — `netbird status/up/down/profile`
    ++ [
      quickshell # `qs` — the shell re-invokes itself for sub-windows
      accounts # `nixbook-accounts` — the accounts, contacts and tasks (services/Accounts.qml)
      keep # `nixbook-keep` — the notes' sync with Google Keep (services/KeepSync.qml)
      mesh # `nixbook-mesh` — the mesh between people's desktops (services/Mesh.qml)
      ytmusic # `nixbook-ytmusic` — YouTube Music in the background (services/YouTubeMusic.qml)
      shell.passthru.pythonEnv
      anthropicUsage # `anthropic-usage` — AnthropicUsage bar widget
      chargeLimit # `nixbook-charge-limit` — the battery panel's charge limit (services/Battery.qml)
      desktopMcp # `nixbook-desktop-mcp` — desktop tools of the AI chat
      updateCheck # `nixbook-update-check` — the update check (services/UpdateState.qml)
      improve # `nixbook-improve` — the desktop agent's fixes to nixbook (services/SelfImprove.qml)
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
  # the shell's clipboard history (Mod+Q) is permanently empty. If either
  # watcher dies, exit non-zero so the unit's Restart=on-failure brings both
  # back (systemd kills the surviving one with the rest of the cgroup).
  cliphistWatch = pkgs.writeShellScript "nixbook-shell-cliphist-watch" ''
    ${pkgs.wl-clipboard}/bin/wl-paste --type text --watch ${pkgs.cliphist}/bin/cliphist store &
    ${pkgs.wl-clipboard}/bin/wl-paste --type image --watch ${pkgs.cliphist}/bin/cliphist store &
    wait -n
    exit 1
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
    # Without it Qt's Wayland plugin gives every window a second OpenGL
    # context, kept to draw a title bar of its own. niri draws none
    # (prefer-no-csd) and sets this for the apps it starts, but the shell is a
    # systemd service: its ~27 surfaces each had one, with three driver threads
    # (about 30 MB and 75 threads for nothing).
    export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
    # Sounds (Audio.playSystemSound: the timers' ringtones, battery) are
    # looked up in XDG_DATA_DIRS; NixOS has no /usr/share/sounds, so the
    # freedesktop theme is always there as the fallback.
    export XDG_DATA_DIRS="''${XDG_DATA_DIRS:-/usr/local/share:/usr/share}:${pkgs.sound-theme-freedesktop}/share"
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
    # The directories services/DesktopControl.qml and SelfImprove.qml watch: a file watch needs
    # its directory to exist when the shell starts (desktop-mcp.py creates
    # them the same way, 0700, on first use).
    if [ "''${1:-}" != "ipc" ]; then
      for dir in "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/nixbook-desktop-mcp" \
        "''${XDG_STATE_HOME:-$HOME/.local/state}/nixbook-shell" \
        "''${XDG_STATE_HOME:-$HOME/.local/state}/nixbook-shell/improve"; do
        [ -d "$dir" ] || mkdir -p -m 700 "$dir"
      done
    fi
    exec ${quickshell}/bin/qs -c ${configName} "$@"
  '';
in
launcher.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    inherit echoCancel;
    inherit
      shell
      quickshell
      accounts
      improve
      configName
      settingsLib
      cliphistWatch
      desktopMcp
      fonts
      keep
      mesh
      ytmusic
      electronBridge
      ;
    zenAgent = {
      extension = zenExtension;
      extensionId = zenExtensionId;
      host = zenBridgeHost;
      bridge = zenBridge;
    };
  };
  meta = shell.meta // {
    mainProgram = "nixbook-shell";
  };
})
