{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.customNixOSModules;
in
{
  imports = [ ];
  config = lib.mkIf cfg.sway.enable {
    programs.sway = {
      enable = true;
      package = pkgs.swayfx;
    };
    # The nixpkgs sway module routes every portal interface to "gtk", which
    # does not implement the Secret portal. Route it to gnome-keyring
    # (backend registered globally by services.gnome.gnome-keyring in core.nix).
    xdg.portal.config.sway."org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
    # Re-unlock the keyring when unlocking the screen with a password
    # (covers sessions where login provided no password, e.g. autologin).
    # The swaylock PAM service itself is created by the nixpkgs sway module.
    security.pam.services.swaylock.enableGnomeKeyring = true;
  };
  options.customNixOSModules.sway = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable the Sway i3-compatible tiling Wayland compositor.

        Sway is a drop-in Wayland replacement for the i3 X11 window manager,
        using the same configuration syntax and keyboard-driven workflow.

        This module uses the SwayFX fork (programs.sway.package = pkgs.swayfx)
        which adds visual effects (blur, rounded corners, shadows) on top of
        vanilla Sway while remaining fully compatible with standard sway configs.

        Used on: anya (primary).
        See also: homeManagerModules/sway/ for per-user compositor configuration.
      '';
    };
  };
}
