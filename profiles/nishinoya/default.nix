{ pkgs, lib, sources, ... }:
let
  overrides = {
    customHomeManagerModules = { };
    imports = [ ./fastfetchConfig.nix ];
  };
  userConfig = import ../../nixosModules/userConfig.nix {
    inherit lib pkgs sources overrides;
  };
in {
  customNixOSModules = {
    workTools.enable = true;
    laptopProfile.enable = true;
    networkManager.enable = true;
    greetd.enable = true;
    hyprland.enable = true;
    caCertificates = {
      didactiklabs.enable = true;
      logicmg.enable = true;
    };
  };
  imports = [
    (userConfig.mkUser {
      username = "aamoyel";
      userImports = [ ./aamoyel ];
    })
  ];
}
