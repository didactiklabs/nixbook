{
  pkgs,
  lib,
  sources,
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
  # security = {
  #   sudo.wheelNeedsPassword = true;
  # };
  # OpenVPN 3 Linux: OpenVPN Inc's official client on Linux (OpenVPN Connect
  # itself only ships for Windows/macOS/mobile). Same profiles (.ovpn,
  # Access Server, CloudConnexa incl. web auth); DNS via systemd-resolved.
  programs.openvpn3.enable = true;
  services = {
    clamav = {
      daemon.enable = true;
      updater.enable = true;
    };
  };
  customNixOSModules = {
    laptopProfile.enable = true;
    # greetd with nixbook-shell's own login screen: the greeter's default
    # when a user runs nixbook-shell (tuigreet stays the fallback).
    greetd.enable = true;
    niri = {
      enable = true;
      # nixbook-shell ships its own polkit agent (see totoro).
      polkitAgent = false;
    };
    caCertificates = {
      bealv.enable = true;
      didactiklabs.enable = true;
      rpcu.enable = true;
    };
    tailscale.enable = true;
    netbird-tools.enable = true;
    firewall.enable = true;
    lanzaboote.enable = true;
    # System-level support (uinput server, udev, per-user service) for the
    # Lotus Vietnamese input method. The fcitx5 addon itself is enabled in
    # the user's Home Manager fcitx5Config (lotus = true).
    fcitx5-lotus = {
      enable = true;
      users = [ "khoa" ];
    };
  };
  boot.blacklistedKernelModules = [ "amdxdna" ];
  imports = [
    ../totoro/hosts.nix
    "${sources.nixos-hardware}/framework/13-inch/amd-ai-300-series"
    (userConfig.mkUser {
      username = "khoa";
      userImports = [ ./khoa ];
      shell = pkgs.zsh;
    })
  ];
}
