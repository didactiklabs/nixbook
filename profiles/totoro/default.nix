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
  # services.udev.extraRules = ''
  #   ACTION=="remove",\
  #    ENV{PRODUCT}=="1050/406/571",\
  #    RUN+="${pkgs.systemd}/bin/loginctl lock-sessions"
  #   ACTION=="remove",\
  #    ENV{PRODUCT}=="1050/402/543",\
  #    RUN+="${pkgs.systemd}/bin/loginctl lock-sessions"
  # '';
  hardware = {
    enableAllFirmware = true;
    bluetooth = {
      powerOnBoot = lib.mkForce true;
    };
  };
  customNixOSModules = {
    workTools.enable = true;
    laptopProfile.enable = true;
    networkManager.enable = true;
    greetd.enable = true;
    hyprland.enable = false;
    niri.enable = true;
    caCertificates = {
      bealv.enable = true;
      didactiklabs.enable = true;
    };
  };
  imports = [
    (userConfig.mkUser {
      username = "khoa";
      userImports = [ ./khoa ];
      shell = pkgs.fish;
    })
  ];
}
