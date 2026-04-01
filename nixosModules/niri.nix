{
  config,
  lib,
  pkgs,
  ...
}:
let
  # NOTE: Must use direct import here instead of the `sources` module arg,
  # because this is used in `imports` which cannot depend on `config`/_module.args.
  sources = import ../npins;
  niri-flake =
    (import sources.flake-compat {
      src = sources.niri-flake;
    }).defaultNix;
  cfg = config.customNixOSModules;
in
{
  imports = [
    niri-flake.nixosModules.niri
  ];
  config = lib.mkIf cfg.niri.enable {
    programs.niri.enable = true;
    programs.niri.package = pkgs.niri;
    systemd.user.services.niri-flake-polkit.enable = false;
    security.pam.services.sddm.enableGnomeKeyring = true;

    # Add GTK portal and route FileChooser to it (avoids Nautilus dependency from GNOME portal)
    # Other settings match niri's shipped niri-portals.conf defaults
    xdg.portal = {
      extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
      config.niri = {
        default = [
          "gnome"
          "gtk"
        ];
        "org.freedesktop.impl.portal.Access" = [ "gtk" ];
        "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
        "org.freedesktop.impl.portal.Notification" = [ "gtk" ];
        "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
      };
    };

    # Ensure the GNOME portal backend auto-starts and restarts on crash
    systemd.user.services.xdg-desktop-portal-gnome = {
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = 3;
      };
    };

    environment.systemPackages = with pkgs; [
      fuzzel
      grimblast
      wl-clipboard
      libnotify
      xwayland-satellite
    ];

    nix.settings = {
      substituters = [
        "https://cache.nixos.org/"
        "https://niri.cachix.org/"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "niri.cachix.org-1:Wv0OmO7PsuocRKzfDoJ3mulSl7Z6oezYhGhR+3W2964="
      ];
    };
  };
  options.customNixOSModules.niri = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable the Niri scrollable-tiling Wayland compositor.

        Niri is a modern Wayland compositor where windows are arranged in an
        infinite horizontal scrollable strip rather than traditional workspaces.

        This module:
        - Imports the niri-flake NixOS module (sourced from npins, not nixpkgs)
        - Enables programs.niri with the nixpkgs niri package
        - Disables the niri-flake bundled polkit agent (the system polkit handles it)
        - Enables GNOME keyring unlock via SDDM PAM integration
        - Installs essential Wayland utilities: fuzzel (launcher), grimblast (screenshots),
          wl-clipboard, libnotify, xwayland-satellite (X11 app compatibility layer)
        - Adds xdg-desktop-portal-gtk for FileChooser (avoids Nautilus dependency)
        - Ensures the GNOME portal backend auto-starts with the session and restarts on crash
        - Adds the niri.cachix.org binary cache for fast pre-built niri packages

        Used on: totoro (primary), nishinoya (primary).
        See also: homeManagerModules/niri/ for per-user compositor configuration.
      '';
    };
  };
}
