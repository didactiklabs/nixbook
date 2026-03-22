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
    nvidia = {
      prime.offload.enable = lib.mkForce false;
      prime.offload.enableOffloadCmd = lib.mkForce false;
      powerManagement.enable = lib.mkForce false;
      powerManagement.finegrained = lib.mkForce false;
      dynamicBoost.enable = lib.mkForce false;
    };
  };
  services.xserver.videoDrivers = lib.mkForce [ "modesetting" ];
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
    "${sources.nixos-hardware}/common/gpu/nvidia/disable.nix"
    (userConfig.mkUser {
      username = "khoa";
      userImports = [ ./khoa ];
      shell = pkgs.zsh;
    })
  ];
}
