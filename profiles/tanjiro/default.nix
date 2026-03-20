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
    networkManager.enable = true;
    greetd.enable = true;
    niri.enable = true;
    caCertificates = {
      bealv.enable = true;
      didactiklabs.enable = true;
    };
    tailscale.enable = false;
    netbird-tools.enable = false;
  };
  imports = [
    (userConfig.mkUser {
      username = "khoa";
      userImports = [ ./khoa ];
      shell = pkgs.zsh;
    })
  ];
}
