{
  pkgs,
  lib,
  sources,
  config,
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
  programs.kdeconnect.enable = true;
  hardware = {
    bluetooth = {
      powerOnBoot = lib.mkForce true;
    };
    nvidia.package = config.boot.kernelPackages.nvidiaPackages.mkDriver {
      version = "580.126.18";
      sha256_64bit = "sha256-p3gbLhwtZcZYCRTHbnntRU0ClF34RxHAMwcKCSqatJ0=";
      sha256_aarch64 = "sha256-pruxWQlLurymRL7PbR24NA6dNowwwX35p6j9mBIDcNs=";
      openSha256 = "sha256-1Q2wuDdZ6KiA/2L3IDN4WXF8t63V/4+JfrFeADI1Cjg=";
      settingsSha256 = "sha256-QMx4rUPEGp/8Mc+Bd8UmIet/Qr0GY8bnT/oDN8GAoEI=";
      persistencedSha256 = "";
    };
  };
  customNixOSModules = {
    laptopProfile.enable = true;
    greetd.enable = true;
    hyprland.enable = false;
    niri.enable = true;
    caCertificates = {
      bealv.enable = true;
      didactiklabs.enable = true;
    };
    lanzaboote.enable = true;
  };
  imports = [
    "${sources.nixos-hardware}/asus/zenbook/um6702"
    (userConfig.mkUser {
      username = "khoa";
      userImports = [ ./khoa ];
      shell = pkgs.zsh;
    })
  ];
}
