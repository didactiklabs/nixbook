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
    };
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

  nixpkgs.config = {
    allowUnfree = true;
    permittedInsecurePackages = [
      "qtwebengine-5.15.19"
    ];
  };

  imports = [
    /etc/nixos/hardware-configuration.nix
    ./nixosModules
    (import "${sources.home-manager}/nixos")
    (import "${sources.agenix}/modules/age.nix")
    hostProfile
  ]
  ++ extraConfig;

  # Swap configuration
  swapDevices = [
    {
      device = "/swapfile";
      size = 16 * 1024; # 16GB in MB
    }
  ];

  networking.firewall.enable = false;
}
