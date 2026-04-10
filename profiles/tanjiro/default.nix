{
  pkgs,
  lib,
  sources,
  ...
}:
let
  overrides = {
    customHomeManagerModules = { };
    imports = [ ./fastfetchConfig.nix ];
  };
  userConfig = import ../../nixosModules/userConfig.nix {
    inherit
      lib
      pkgs
      sources
      overrides
      ;
  };
in
{
  networking.hosts = {
    "10.207.7.1" = [
      "anya"
    ];
    "10.207.7.2" = [
      "gojo"
    ];
  };
  security = {
    sudo.wheelNeedsPassword = true;
  };
  services = {
    clamav = {
      daemon.enable = true;
      updater.enable = true;
    };
  };
  customNixOSModules = {
    laptopProfile.enable = true;
    greetd.enable = true;
    niri.enable = true;
    caCertificates = {
      bealv.enable = true;
      didactiklabs.enable = true;
    };
    tailscale.enable = true;
    netbird-tools.enable = false;
    firewall.enable = true;
    lanzaboote.enable = true;
  };
  boot.blacklistedKernelModules = [ "amdxdna" ];
  imports = [
    "${sources.nixos-hardware}/framework/13-inch/amd-ai-300-series"
    (userConfig.mkUser {
      username = "khoa";
      userImports = [ ./khoa ];
      shell = pkgs.zsh;
    })
  ];
}
