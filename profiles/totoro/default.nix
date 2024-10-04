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
    "100.111.17.126" = [
      "gitea"
      "git.s3ns.internal"
    ];
  };
  security.pam.yubico = {
    enable = true;
    debug = true;
    mode = "challenge-response";
    id = [ "29513678" ];
  };
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
      bealv.enable = true;
      didactiklabs.enable = true;
    };
  };
  imports = [
    (userConfig.mkUser {
      username = "khoa";
      userImports = [ ./khoa ];
    })
  ];
}
