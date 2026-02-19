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
    nixosUpdate.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable NixOS update plugin";
    };
    sathiAi.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Sathi AI plugin";
    };
  };

  config = lib.mkIf config.customHomeManagerModules.dmsConfig.enable {
    home.sessionVariables = {
      QS_ICON_THEME = "Numix-Square";
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
            ]
            ++ lib.optional config.customHomeManagerModules.dmsConfig.nixosUpdate.enable "nixosUpdate"
            ++ [
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
              "netbirdStatus"
              "tailscaleStatus"
              "cpuUsage"
              "notificationButton"
              "battery"
              "controlCenterButton"
              {
                id = "powerMenuButton";
                enabled = true;
              }
            ]
            ++ lib.optional config.customHomeManagerModules.dmsConfig.sathiAi.enable "sathiAi";
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
        dankGifSearch.enable = true;
        dankStickerSearch.enable = true;
        tailscale.enable = false;
        tailscaleStatus = {
          enable = true;
          settings = {
            autoConnect = false;
          };
          src = ../assets/dms/plugins/tailscale-dms;
        };
        netbirdStatus = {
          enable = true;
          settings = {
            autoConnect = false;
          };
          src = ../assets/dms/plugins/netbird-dms;
        };
        sathiAi = {
          inherit (config.customHomeManagerModules.dmsConfig.sathiAi) enable;
          src = lib.mkForce ../assets/dms/plugins/sathi-ai;
          settings = {
            resizeCorner = "left";
          };
        };
        nixosUpdate = {
          inherit (config.customHomeManagerModules.dmsConfig.nixosUpdate) enable;
          src = ../assets/dms/plugins/nixos-update;
          settings = {
            repoUrl = "https://github.com/didactiklabs/nixbook";
            updateCommand = "osupdate";
          };
        };
      };
    };
  };
}
