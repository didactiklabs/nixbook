{
  config,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules;
  # Desktop entries for non-user-facing utilities, settings tools, background
  # daemons and duplicate launchers that only clutter the application launcher.
  # Each name must match the original <name>.desktop filename so the generated
  # entry shadows the original. Home Manager's xdg.desktopEntries adds these as
  # hiPrio desktop-item packages to the user profile, overriding the originals
  # there. Entries installed system-wide (e.g. qt5ct/qt6ct) are hidden
  # separately in nixosModules/userConfig.nix.
  hiddenEntries = [
    # Qt / theme settings tools
    "qt5ct"
    "qt6ct"
    "kvantummanager"
    # fcitx5 daemon, settings GUIs, helper / duplicate launchers
    "org.fcitx.Fcitx5"
    "org.fcitx.Fcitx5.Addon.Lotus.Settings"
    "org.fcitx.fcitx5-qt5-gui-wrapper"
    "org.fcitx.fcitx5-qt6-gui-wrapper"
    "org.fcitx.fcitx5-migrator"
    "org.fcitx.fcitx5-config-qt"
    "fcitx5-configtool"
    "fcitx5-wayland-launcher"
    "kcm_fcitx5"
    # KDE Connect background / handler entries (keep the main app)
    "org.kde.kdeconnect.daemon"
    "org.kde.kdeconnect.handler"
    "org.kde.kdeconnect.nonplasma"
    "org.kde.kdeconnect.sms"
    # geoclue demos + pinentry dialog
    "geoclue-demo-agent"
    "geoclue-where-am-i"
    "org.gnupg.pinentry-qt"
    # NetworkManager connection editor (settings tool)
    "nm-connection-editor"
    # Manual + xdg desktop portals
    "nixos-manual"
    "xdg-desktop-portal-gnome"
    "xdg-desktop-portal-gtk"
    # CLI/TUI tools and helper launchers with no real GUI app
    "khal"
    "umpv"
    "imv-dir"
    "kbd-layout-viewer5"
    # DMS/Quickshell runtime backend + umlaut gesture editor
    "org.quickshell"
    "schnelle-umlaute-editor"
  ];
in
{
  options.customHomeManagerModules.desktopEntriesConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to hide desktop launcher entries for non-user-facing utilities,
        settings tools, background daemons and duplicate launchers (e.g.
        kvantummanager, fcitx5 daemon/helpers/config GUIs, KDE Connect daemon
        entries, geoclue demos, pinentry, nm-connection-editor, xdg portals,
        khal, umpv, imv-dir, kbd-layout-viewer, quickshell, nixos-manual).

        Implemented via hiPrio desktop-item packages with NoDisplay=true that
        shadow the originals in the user profile. System-wide qt5ct/qt6ct are
        hidden separately in nixosModules/userConfig.nix.
      '';
    };
  };

  config = lib.mkIf cfg.desktopEntriesConfig.enable {
    xdg.desktopEntries = lib.genAttrs hiddenEntries (_: {
      name = "";
      noDisplay = true;
    });
  };
}
