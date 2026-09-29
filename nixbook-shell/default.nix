# nixbook-shell — a Quickshell (QML) desktop shell for niri.
# Self-contained: nothing here reaches outside this directory, so it can be
# used (or split into its own repository) without the rest of nixbook.
#
#   import ./nixbook-shell { }                     # own pins (npins/)
#   import ./nixbook-shell { inherit pkgs; }       # your nixpkgs
#
# gives:
#   package                      the `nixbook-shell` launcher (package.nix), with
#                                DankCalendar (`dcal`, dankcalendar.nix)
#   homeManagerModules.default   programs.nixbook-shell (hm-module.nix)
#   nixosModules.default         the NixOS toggles for its assistant (nixos-module.nix)
#                                and the login screen (greeter.nix, nixbook-shell.greeter)
#   lib                          the settings helpers (lib.nix)
{
  sources ? import ./npins,
  pkgs ? import sources.nixpkgs { },
  # A quickshell checkout with a `revision` attribute (an npins pin).
  quickshellSrc ? sources.quickshell,
  # DankCalendar's source (a flake) and flake-compat to evaluate it.
  dankcalendarSrc ? sources.dankcalendar,
  flakeCompatSrc ? sources.flake-compat,
}:
{
  package = import ./package.nix {
    inherit
      pkgs
      quickshellSrc
      dankcalendarSrc
      flakeCompatSrc
      ;
  };
  homeManagerModules.default = ./hm-module.nix;
  nixosModules.default = ./nixos-module.nix;
  lib = import ./lib.nix { inherit (pkgs) lib; };
}
