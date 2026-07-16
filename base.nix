{
  config,
  hostname,
  lib,
  ...
}:
let
  sources = import ./npins;
  pkgs = import sources.nixpkgs {
    config = {
      allowUnfree = true;
      allowUnfreePredicate = true;
      permittedInsecurePackages = [
        "qtwebengine-5.15.19"
        "pnpm-10.29.2"
        "electron-40.10.5"
      ];
    };
    overlays = [
      (import ./nixosModules/overlays.nix { inherit sources; })
    ];
  };
  hostProfile = import ./profiles/${hostname} {
    inherit
      lib
      config
      hostname
      sources
      pkgs
      ;
  };
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

  imports = [
    /etc/nixos/hardware-configuration.nix
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
