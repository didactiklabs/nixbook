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
  # Moonlight streaming over Wi-Fi had a jitter burst every 5 min 9 s: a
  # background scan. NetworkManager gives wpa_supplicant bgscan
  # "simple:30:-65:300" (every 300 s) once a connection has seen more than
  # one BSSID, else "simple:30:-70:86400" (nm-supplicant-config.c); the home
  # GL.iNet router changes its BSSID (28 recorded), so it counted as a
  # multi-AP network. Forgetting the seen BSSIDs at each start leaves one per
  # boot (they are recorded on connection only), while real multi-AP
  # networks still collect several within a boot and keep roaming scans.
  systemd.services.NetworkManager.serviceConfig.ExecStartPre = [
    "-${pkgs.coreutils}/bin/rm -f /var/lib/NetworkManager/seen-bssids"
  ];
  # Radio naps between packets added late wake-ups to a steady 70 Mbit/s stream.
  networking.networkmanager.wifi.powersave = false;
  customNixOSModules = {
    # Panel Self Refresh back on for the OLED (idle battery), minus Selective
    # Update. If the amdgpu freezes return, set "off" (see core.amdgpuPsr).
    core.amdgpuPsr = "no-su";
    laptopProfile = {
      enable = true;
      # 2.7 GHz instead of 4.77: cooler (86 °C at 11 W with boost), and the
      # Radeon 680M gets more of the shared power budget in games.
      cpuBoost = false;
      # The battery is down to half its capacity after two years charged to
      # 100 %. The battery panel of the bar changes it (100 before a trip).
      chargeLimit = 80;
    };
    # greetd with nixbook-shell's own login screen: the greeter's default
    # when a user runs nixbook-shell (tuigreet stays the fallback).
    greetd.enable = true;
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
    # Steam, Proton, GameMode. Not gpu = "amd": that tuning is for desktops
    # (an 8 GB TTM page pool on this 14 GiB laptop, IOMMU off, and its own
    # dcdebugmask would replace core.amdgpuPsr above).
    gamingConfig = {
      enable = true;
      gpu = "none";
    };
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
