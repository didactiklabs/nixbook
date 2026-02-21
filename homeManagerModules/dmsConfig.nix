{
  config,
  pkgs,
  lib,
  ...
}:
let
  sources = import ../npins;
  dmsFlake = import sources.flake-compat {
    src = sources.dms;
  };
  dmsPluginRegistryFlake = import sources.flake-compat {
    src = sources.dms-plugin-registry;
  };
  pkgs-unstable = import sources.nixpkgs-unstable { };
in
{
  imports = [
    dmsFlake.defaultNix.homeModules.dank-material-shell
    dmsPluginRegistryFlake.defaultNix.modules.default
  ];

  options.customHomeManagerModules.dmsConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "";
    };
    showDock = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Show the dock";
    };
  };

  config = lib.mkIf config.customHomeManagerModules.dmsConfig.enable {
    home.sessionVariables = {
      QS_ICON_THEME = "Papirus-Dark";
    };
    services.blueman-applet.enable = lib.mkForce false;
    programs.dank-material-shell = {
      enable = true;
      systemd = {
        enable = true; # Systemd service for auto-start
        restartIfChanged = true; # Auto-restart dms.service when dms-shell changes
      };
      # Core features
      enableSystemMonitoring = true; # System monitoring widgets (dgop)
      enableDynamicTheming = true; # Wallpaper-based theming (matugen)
      enableAudioWavelength = true; # Audio visualizer (cava)
      enableCalendarEvents = true; # Calendar integration (khal)
      dgop.package = pkgs-unstable.dgop;
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
              "idleInhibitor"
            ];
            centerWidgets = [
              "music"
              "clock"
              "weather"
            ];
            rightWidgets = [
              "systemTray"
              "vpnStatus"
              "cpuUsage"
              "notificationButton"
              "battery"
              "controlCenterButton"
              {
                id = "powerMenuButton";
                enabled = true;
              }
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
      };
      managePluginSettings = false;
      plugins = {
        dankBatteryAlerts.enable = true;
        dankGifSearch.enable = true;
        dankStickerSearch.enable = true;
        tailscale.enable = false;
        vpnStatus = {
          enable = true;
          src = ../assets/dms/plugins/vpn-dms;
        };
        sathiAi = {
          enable = true;
        };
        nixosUpdate = {
          enable = true;
          src = ../assets/dms/plugins/nixos-update;
        };
      };
    };
  };
}
