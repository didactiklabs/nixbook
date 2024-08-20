{ pkgs, lib, sources, ... }:
let
  overrides = {
    customHomeManagerModules = { };
    imports = [ ./fastfetchConfig.nix ];
  };
  userConfig = import ../../nixosModules/userConfig.nix {
    inherit lib pkgs sources;
    overrides = overrides;
  };
  mkUser = userConfig.mkUser;
in {
  networking.hosts = { "100.111.17.126" = [ "gitea" "git.s3ns.internal" ]; };
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
