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
    workTools.enable = true;
    laptopProfile.enable = true;
    networkManager.enable = true;
    greetd.enable = true;
    hyprland.enable = true;
    caCertificates = {
      bealv.enable = true;
      didactiklabs.enable = true;
    };
  };
  imports = [
    (mkUser {
      username = "khoa";
      userImports = [ ./khoa ];
    })
  ];
}
