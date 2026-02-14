{
  config,
  # pkgs,
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
  pkgs = import sources.nixpkgs { };
  pkgs-unstable = import sources.nixpkgs-unstable { };
in
{
  imports = [
    dmsFlake.defaultNix.homeModules.dank-material-shell
    dmsFlake.defaultNix.homeModules.niri
    dmsPluginRegistryFlake.defaultNix.modules.default
  ];

  options.customHomeManagerModules.dmsConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "";
    };
  };

  config = lib.mkIf config.customHomeManagerModules.dmsConfig.enable {
    services.blueman-applet.enable = lib.mkForce false;
    programs.dank-material-shell = {
      enable = true;
      niri = lib.mkIf config.customHomeManagerModules.niriConfig.enable {
        enableSpawn = true; # Auto-start DMS with niri, if enabled
        includes = {
          enable = false;
        };
      };
      systemd = lib.mkIf (!config.customHomeManagerModules.niriConfig.enable) {
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
              "clipboard"
              "cpuUsage"
              "memUsage"
              "notificationButton"
              "battery"
              "controlCenterButton"
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
            fontFamily = "Hack Nerd Font"; # Added to fix missing tray icons
            monoFontFamily = "Fira Code";
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
      plugins = {
        dankBatteryAlerts.enable = true;
      };
    };
  };
}
