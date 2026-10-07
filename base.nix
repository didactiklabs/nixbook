{
  config,
  hostname,
  lib,
  ...
}:
let
  sources = import ./npins;
  pkgs = import ./lib/pkgs.nix { inherit sources; };
  hostProfile = import ./profiles/${hostname} {
    inherit
      lib
      config
      hostname
      sources
      pkgs
      ;
  };
  # The installer evaluates the target system from the live ISO, before
  # /etc/nixos exists: it points this at /mnt/etc/nixos/hardware-configuration.nix.
  hardwareConfig =
    let
      override = builtins.getEnv "NIXBOOK_HARDWARE_CONFIG";
    in
    if override != "" then /. + override else /etc/nixos/hardware-configuration.nix;
  extraConfig =
    if builtins.pathExists /etc/nixos/extraConfiguration.nix then
      [ /etc/nixos/extraConfiguration.nix ]
    else
      [ ];
in
{
  _module.args = {
    inherit sources;
    hostname = config.networking.hostName;
  };

  # Evaluate the system with the same nixpkgs instance as the profiles (one
  # instance instead of two). Without it NixOS builds its own from the
  # nixpkgs.config/overlays colmena copies over from meta.nixpkgs. Those two
  # are forced empty here (nixpkgs requires that with nixpkgs.pkgs; they are
  # already part of this instance): add config and overlays in lib/pkgs.nix
  # and lib/overlays.nix, not through the nixpkgs.* options.
  nixpkgs = {
    inherit pkgs;
    config = lib.mkForce { };
    overlays = lib.mkForce [ ];
  };

  imports = [
    hardwareConfig
    ./nixosModules
    (import "${sources.home-manager}/nixos")
    (import "${sources.agenix}/modules/age.nix")
    (import "${sources.lanzaboote}" {
      inherit pkgs;
      crane = import "${sources.crane}" { inherit pkgs; };
      inherit (sources) rust-overlay;
    }).nixosModules.lanzaboote
    hostProfile
  ]
  ++ extraConfig;
}
