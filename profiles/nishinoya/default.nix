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
  services.udev.extraRules = ''
    ACTION=="remove",\
     ENV{ID_BUS}=="usb",\
     ENV{ID_MODEL_ID}=="0407",\
     ENV{ID_VENDOR_ID}=="1050",\
     ENV{ID_VENDOR}=="Yubico",\
     RUN+="${pkgs.systemd}/bin/loginctl lock-sessions"
  '';
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
  boot.kernel.sysctl = {
    "net.ipv4.ip_unprivileged_port_start" = 80;
  };
  imports = [
    (userConfig.mkUser {
      username = "aamoyel";
      userImports = [ ./aamoyel ];
    })
  ];
}
