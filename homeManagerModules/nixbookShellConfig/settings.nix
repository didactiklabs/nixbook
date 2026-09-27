# nixbook-shell settings shared by every machine running the shell (the defaults of
# customHomeManagerModules.nixbookShellConfig.settings; a profile's own `settings`
# override them key by key). Every key here, and every key in a profile's
# `nixbookShellConfig.settings`, is applied on each
# activation and shown LOCKED in the Settings menu (red lock, control
# disabled). The lock list is generated from these attrsets at build time, so
# deleting a line here (or in a profile) unlocks that setting in the running
# shell after the next switch; anything not set in Nix keeps the shell's
# built-in default and stays editable from the menu, persisting across
# restarts and switches.
#
# Only list values that differ from the shell's built-in defaults
# (builtin-defaults.json, i.e. upstream's modules/common/Config.qml).
# `nixbook-shell config diff` prints the settings you changed from the menu as Nix
# lines, ready to paste here or into a profile's `nixbookShellConfig.settings`.
{
  appearance = {
    palette = {
      type = "scheme-neutral";
    };
    transparency = {
      enable = true;
    };
    wallpaperTheming = {
      enableQtApps = false;
      # Don't recolour terminals from the wallpaper: upstream's applycolor.sh
      # rewrites kitty's theme and blasts OSC colour sequences into every
      # /dev/pts/*, fighting stylix (stylixConfig.nix + kittyConfig.nix own
      # terminal theming here). The shell's own palette is unaffected.
      enableTerminal = false;
      # Keep on (and locked): it gates an early `return` in switchwall.sh, so
      # turning it off stops palette regeneration entirely and silently breaks
      # the shell's light/dark switch. Use enableTerminal for the terminal.
      enableAppsAndShell = true;
    };
  };
  apps = {
    taskManager = "kitty -1 -e btop";
  };
  background = {
    centeredWallpaperShape = "Heart";
    wallpaperAnimation = "Doom";
  };
  bar = {
    cornerStyle = 1;
    layouts = {
      leftLayout = [
        "launcherButton"
        "workspaces"
        "activeWindow"
        "leftSidebarButton"
      ];
      middleLayout = [
        "clockWidget"
        "kdeConnect"
        "resources"
        "networkSpeed"
        "anthropicUsage"
      ];
      rightLayout = [
        "sysTray"
        "utilButtons"
        "systemIcons"
        "vpnStatus"
        "batteryIndicator"
        "powerButton"
        "updatesCount"
      ];
    };
    weather = {
      city = "Mérignac";
    };
  };
  dock = {
    enable = true;
    monochromeIcons = false;
    pinnedApps = [
      "org.kde.dolphin"
      "kitty"
      "zen-twilight"
    ];
    showAppsButton = false;
    showPinButton = false;
  };
  lock = {
    blur = {
      enable = false;
    };
  };
  notifications = {
    # Popup duration in ms (built-in 7000) for notifications that don't set
    # their own expiry; hovering a popup still pauses it.
    timeout = 15000;
    # Messages from people stay on screen until dismissed. Matched on the app
    # name (exact) or keywords in the app name / title / notification hints
    # (not the message text), case-insensitive — browser notifications come
    # from the browser (e.g. "Twilight") with the site in the title.
    persistent = {
      apps = [
        "Vesktop"
        "Slack"
      ];
      keywords = [
        "Discord"
        "Slack"
        "WhatsApp"
        "Instagram"
        "Facebook"
        "Messenger"
      ];
    };
    # Persona style: full-screen cut-in for critical notifications and for
    # these keywords (app name, title, text or hints).
    cutIn.keywords = [
      "Google Calendar"
      "Google Agenda"
      "calendar.google.com"
      "Alesio"
      "alesio"
      "chocomooncake"
      "choco mooncake"
      "huyền"
      "wolfey182"
      "Huyen"
      "HUYEN NGUYEN"
      "Diệu Huyền Nguyễn"
      "Diệu"
      "Diệu Huyền"
      "Trang HANG"
      "Tin Dinh"
      "aamoyel"
      "Alan Amoyel"
      "vtk_hg"
      "Victor Tiến Khoa Hang"
      "Victor Tiến Khoa"
      "Victor Hang"
      "ビクタ"
      "victortk"
    ];
  };
  overlay = {
    openingZoomAnimation = false;
  };
  overview = {
    enable = false;
  };
  sidebar = {
    cornerOpen = {
      clicklessCornerEnd = false;
      enable = false;
    };
    mediaPlayer = false;
    quickSliders = {
      showMic = true;
    };
  };
  sounds = {
    battery = true;
  };
  time = {
    secondPrecision = true;
  };
}
