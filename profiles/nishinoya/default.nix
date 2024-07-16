{ pkgs, lib, stylix, nixvim, ... }:
let
  overrides = {
    customHomeManagerModules = { };
    imports = [ ./fastfetchConfig.nix ];
  };
  userConfig = import ../../nixosModules/userConfig.nix {
    inherit lib pkgs stylix nixvim;
    overrides = overrides;
  };
  mkUser = userConfig.mkUser;
in {
  customNixOSModules = {
    laptopProfile.enable = true;
    networkManager.enable = true;
    sunshine.enable = false;
    greetd.enable = true;
    sway.enable = false;
    hyprland.enable = true;
    caCertificates = { didactiklabs.enable = true; };
  };
  imports = [
    (mkUser {
      username = "aamoyel";
      userImports = [ ./aamoyel ];
    })
  ];
}
