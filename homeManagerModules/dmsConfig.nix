{
  config,
  pkgs,
  lib,
  ...
}:
let
  sources = import ../npins;
  quickshellOverlay = (import "${sources.quickshell}/overlay.nix") {
    rev = sources.quickshell.revision;
  };
  quickshellPkg = (quickshellOverlay pkgs pkgs).quickshell;
in
{
  options.customHomeManagerModules.dmsConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable DankMaterialShell (DMS) desktop shell.

        DMS is a Quickshell-based desktop shell providing a customisable top bar
        and optional dock.  It is compositor-agnostic (works with niri, sway,
        hyprland) and integrates deeply with the rest of this configuration.

        Features enabled:
          - System monitoring widgets powered by dgop
          - Dynamic wallpaper-based theming via matugen (scheme-vibrant)
          - Audio wavelength visualiser via cava
          - Calendar event integration via khal
          - Systemd user service with auto-restart on config change

        Bar layout (single "Main Bar" on all screens):
          Left:   launcherButton, nixosUpdate, workspaceSwitcher,
                  focusedWindow, idleInhibitor
          Centre: music, clock, weather, opencodeUsage
          Right:  systemTray, vpnStatus, cpuUsage, notificationButton,
                  dankKDEConnect, battery, controlCenterButton,
                  powerMenuButton, sathiAi

        Plugins bundled:
          - dankBatteryAlerts     — low battery notifications
          - dankGifSearch         — GIF search widget
          - dankStickerSearch     — sticker search widget
          - dankKDEConnect        — KDE Connect integration (auto-enabled with kdeconnect)
          - vpnStatus             — Tailscale/NetBird VPN indicator (custom, from assets/)
          - sathiAi               — AI assistant widget
          - opencodeUsage         — OpenCode token usage display (when opencodeConfig enabled)
          - nixosUpdate           — NixOS update trigger widget (calls osupdate via systemd)

        Also registers a nixos-upgrade-manual systemd oneshot service used by
        the nixosUpdate bar widget to apply system updates without a terminal.

        When dmsConfig is enabled, stylixConfig forces the tomorrow-night base16
        scheme for colour consistency.
      '';
    };
    showDock = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to show the application dock below the bar.

        When true, a dock with running/pinned application icons appears at the
        bottom of the screen.  Dock appearance is controlled by the dockTransparency,
        dockBottomGap, dockMargin, dockIconSize, and dockIndicatorStyle settings.
      '';
    };
    enableNixosUpdate = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to enable the nixosUpdate DMS bar widget and the accompanying
        nixos-upgrade-manual systemd oneshot service.

        When true, the nixosUpdate plugin (from assets/dms/plugins/nixos-update) is
        loaded into the bar and a systemd user service is registered so the widget
        can trigger a system upgrade (via osupdate) without opening a terminal.

        Disable this on machines where the widget is not desired or where the
        osupdate script is unavailable.
      '';
    };
  };

  config = lib.mkIf config.customHomeManagerModules.dmsConfig.enable {
    home.sessionVariables = {
      QS_ICON_THEME = "Papirus-Dark";
    };
    programs.dank-material-shell = {
      enable = true;
      quickshell = {
        package = quickshellPkg;
      };
      systemd = {
        enable = true; # Systemd service for auto-start
        restartIfChanged = true; # Auto-restart dms.service when dms-shell changes
      };
      # Core features
      enableSystemMonitoring = true; # System monitoring widgets (dgop)
      enableDynamicTheming = true; # Wallpaper-based theming (matugen)
      enableAudioWavelength = true; # Audio visualizer (cava)
      enableCalendarEvents = true; # Calendar integration (khal)
      dgop.package = pkgs.dgop;
      settings = {
        useAutoLocation = true;
        nightModeEnabled = true;
        launcherLogoMode = "os";
        currentThemeName = "dynamic";
        matugenScheme = "scheme-vibrant";
        osdAlwaysShowValue = true;
        osdPowerProfileEnabled = true;
        dockTransparency = 0.7;
        dockBottomGap = -15;
        dockMargin = 5;
        dockIconSize = 35;
        dockIndicatorStyle = "line";
        dockIsolateDisplays = true;
        showOccupiedWorkspacesOnly = true;
        runningAppsCompactMode = true;
        focusedWindowCompactMode = true;
        inherit (config.customHomeManagerModules.dmsConfig) showDock;
        barConfigs = [
          {
            id = "default";
            name = "Main Bar";
            enabled = true;
            position = 0;
            screenPreferences = [ "all" ];
            showOnLastDisplay = true;
            leftWidgets = [
              "launcherButton"
              "nixosUpdate"
              "workspaceSwitcher"
              "focusedWindow"
            ];
            centerWidgets = [
              "music"
              "clock"
              "weather"
              "opencodeUsage"
              "githubNotifierCustom"
            ];
            rightWidgets = [
              "systemTray"
              "vpnStatus"
              "cpuUsage"
              "notificationButton"
              "dankKDEConnect"
              "controlCenterButton"
              "sathiAi"
            ];
            spacing = 4;
            innerPadding = 4;
            bottomGap = 0;
            transparency = 0.7;
            widgetTransparency = 1.0;
            squareCorners = false;
            noBackground = false;
            gothCornersEnabled = false;
            gothCornerRadiusOverride = false;
            gothCornerRadiusValue = 12;
            borderEnabled = false;
            borderColor = "surfaceText";
            borderOpacity = 1.0;
            borderThickness = 1;
            widgetOutlineEnabled = false;
            widgetOutlineColor = "primary";
            widgetOutlineOpacity = 1.0;
            widgetOutlineThickness = 1;
            fontScale = 1.0;
            fontFamily = "Roboto"; # Added to fix missing tray icons
            monoFontFamily = "Roboto Mono";
            autoHide = false;
            autoHideDelay = 250;
            showOnWindowsOpen = false;
            openOnOverview = false;
            visible = true;
            popupGapsAuto = true;
            popupGapsManual = 4;
            maximizeDetection = true;
            scrollEnabled = true;
            scrollXBehavior = "column";
            scrollYBehavior = "workspace";
            shadowIntensity = 0;
            shadowOpacity = 60;
            shadowColorMode = "text";
            shadowCustomColor = "#000000";
            clickThrough = false;
          }
        ];
        controlCenterShowNetworkIcon = true;
        controlCenterShowBluetoothIcon = true;
        controlCenterShowAudioIcon = true;
        controlCenterShowAudioPercent = true;
        controlCenterShowVpnIcon = true;
        controlCenterShowBrightnessIcon = true;
        controlCenterShowBrightnessPercent = true;
        controlCenterShowMicIcon = false;
        controlCenterShowMicPercent = false;
        controlCenterShowBatteryIcon = true;
        controlCenterShowPrinterIcon = false;
        controlCenterShowScreenSharingIcon = true;
        controlCenterWidgets = [
          {
            id = "volumeSlider";
            enabled = true;
            width = 50;
          }
          {
            id = "brightnessSlider";
            enabled = true;
            width = 50;
          }
          {
            id = "wifi";
            enabled = true;
            width = 50;
          }
          {
            id = "bluetooth";
            enabled = true;
            width = 50;
          }
          {
            id = "audioOutput";
            enabled = true;
            width = 50;
          }
          {
            id = "audioInput";
            enabled = true;
            width = 50;
          }
          {
            id = "battery";
            enabled = true;
            width = 25;
          }
          {
            id = "idleInhibitor";
            enabled = true;
            width = 25;
          }
          {
            id = "nightMode";
            enabled = true;
            width = 25;
          }
          {
            id = "darkMode";
            enabled = true;
            width = 25;
          }
        ];
      };
      managePluginSettings = false;
      plugins = {
        dankBatteryAlerts.enable = true;
        dankGifSearch.enable = true;
        dankStickerSearch.enable = true;
        dankKDEConnect.enable = config.services.kdeconnect.enable;
        vpnStatus = {
          enable = true;
          src = ../assets/dms/plugins/vpn-dms;
        };
        sathiAi = {
          enable = true;
        };
        audioInhibit = {
          enable = true;
        };
        githubNotifierCustom = {
          enable = true;
          src = ../assets/dms/plugins/github-notifier-custom;
        };
        opencodeUsage = {
          inherit (config.customHomeManagerModules.opencodeConfig) enable;
          src = ../assets/dms/plugins/opencode-usage;
        };
        nixosUpdate = lib.mkIf config.customHomeManagerModules.dmsConfig.enableNixosUpdate {
          enable = true;
          src = ../assets/dms/plugins/nixos-update;
        };
      };
    };
  };
}
