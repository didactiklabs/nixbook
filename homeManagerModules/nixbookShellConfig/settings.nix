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
# (nixbook-shell/builtin-defaults.json, i.e. src/modules/common/Config.qml).
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
    # wallpaperAnimation: chosen in the menu (Settings > Desktop).
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
        # "nextEvent"
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
        "desktopControl"
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
        # SMS through Google Messages in the browser (the title is the
        # phone number; the site is in the notification hints).
        "messages.google.com"
      ];
    };
    # No popup, cut-in or chime (still in the notification centre and the
    # history): calendar reminders DankCalendar already shows, as the
    # phone's Google Calendar app mirrors them (KDE Connect, title
    # "Calendar"/"Agenda") and as Google Calendar in the browser does
    # (the site in the notification hints).
    quiet.keywords = [
      "app:KDE Connect + title:^\"Calendar\""
      "app:KDE Connect + title:^\"Agenda\""
      "hint:calendar.google.com"
    ];
    # Persona style: full-screen cut-in for critical notifications and
    # calendar reminders (DankCalendar's; the other copies are quiet above);
    # people (friends, mentions of the user) are personal and
    # added per user profile (e.g. profiles/totoro/khoa). Rules are matched
    # case-insensitively on app name, title, text and hints; "a + b" needs
    # both, "!a" absent, "app:/title:/body:/hint:" one field, quotes a whole
    # word, "^" the start of the field (NotificationUtils.ruleMatches). Test
    # them live in Settings → Notifications → Persona cut-in.
    cutIn.keywords = [
      "app:^\"Dank Calendar\""
    ];
    # Never a cut-in, whatever matched above: my own replies. The phone
    # updates the chat notification with the message I just sent and KDE
    # Connect mirrors it (the whole thread, my message last), so it would
    # match the friend's rule. "last:" is that last message; mine start with
    # "You: …" (or the user's own name, in the profile).
    cutIn.blacklist = [
      "last:^\"You:\""
      "last:^\"Vous:\""
      "last:^\"Bạn:\""
    ];
  };
  overlay = {
    openingZoomAnimation = false;
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
  # The bar's update indicator (UpdatesCount) compares /etc/nixos/version
  # with this repository's main branch.
  updates = {
    repoUrl = "https://github.com/didactiklabs/nixbook";
  };
}
