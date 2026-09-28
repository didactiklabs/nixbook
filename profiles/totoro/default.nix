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
    imports = [
      ./fastfetchConfig.nix
    ];
  };
  userConfig = import ../../lib/userConfig.nix {
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
    greetd = {
      enable = true;
      # ReGreet in nixbook-shell's style (khoa's Persona/palette and login
      # screen wallpaper), instead of tuigreet.
      greeter = "nixbook-shell";
    };
    hyprland.enable = false;
    niri = {
      enable = true;
      # nixbook-shell ships its own polkit agent; running polkit-gnome as well just
      # means the shell's never registers. See customNixOSModules.niri.polkitAgent.
      polkitAgent = false;
    };
    caCertificates = {
      rpcu.enable = true;
      bealv.enable = true;
      didactiklabs.enable = true;
    };
    lanzaboote.enable = true;
    # System-level support (uinput server, udev, per-user service) for the
    # Lotus Vietnamese input method. The fcitx5 addon itself is enabled in
    # the user's Home Manager fcitx5Config (lotus = true).
    fcitx5-lotus = {
      enable = true;
      users = [ "khoa" ];
    };
  };
  imports = [
    ./hosts.nix
    "${sources.nixos-hardware}/asus/zenbook/um6702"
    "${sources.nixos-hardware}/common/gpu/nvidia/disable.nix"
    (userConfig.mkUser {
      username = "khoa";
      userImports = [ ./khoa ];
      shell = pkgs.zsh;
    })
  ];
}
