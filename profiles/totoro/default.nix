{
  config,
  pkgs,
  lib,
  home-manager,
  stylix,
  nixvim,
  ...
}: let
  overrides = {
    customHomeManagerModules = {
    };
    imports = [
      ./fastfetchConfig.nix
    ];
  };
  userConfig = import ../../nixosModules/userConfig.nix {
    inherit lib pkgs home-manager stylix nixvim config;
    overrides = overrides;
  };
  mkUser = userConfig.mkUser;
in {
  customNixOSModules = {
    laptopProfile.enable = true;
    networkManager.enable = true;
    sunshine.enable = false;
    greetd.enable = true;
    sway.enable = true;
    hyprland.enable = true;
  };
  imports = [
    (mkUser {
      username = "khoa";
      userImports = [
        ./khoa
      ];
    })
  ];
}
