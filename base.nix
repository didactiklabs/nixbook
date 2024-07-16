{ config, hostname, lib, ... }:
let
  nixOS_version = "24.05";
  nixvim = pkgs.fetchFromGitHub {
    owner = "nix-community";
    repo = "nixvim";
    rev = "nixos-${nixOS_version}";
    sha256 = "sha256-dQGvOK+t45unF7DTp5bfO37hY0NkDUw6X3MH5CCTEAs=";
  };
  stylix = pkgs.fetchFromGitHub {
    owner = "danth";
    repo = "stylix";
    rev = "release-${nixOS_version}";
    sha256 = "sha256-A+dBkSwp8ssHKV/WyXb9uqIYrHBqHvtSedU24Lq9lqw=";
  };
  pkgs = import (fetchTarball
    "https://github.com/NixOS/nixpkgs/archive/nixos-${nixOS_version}.tar.gz")
    { };
  home-manager = builtins.fetchTarball
    "https://github.com/nix-community/home-manager/archive/release-${nixOS_version}.tar.gz";
  hostProfile = import ./profiles/${hostname} {
    inherit lib config pkgs hostname home-manager stylix nixvim;
  };
in {
  imports = [
    ./hardware-configuration.nix
    ./tools.nix
    ./nixosModules/caCertificates.nix
    ./nixosModules/laptopProfile.nix
    ./nixosModules/greetd.nix
    ./nixosModules/sway.nix
    ./nixosModules/hyprland.nix
    (import ./nixosModules/networkManager.nix { inherit lib config pkgs; })
    (import ./nixosModules/sunshine.nix { inherit lib config pkgs; })
    (import "${home-manager}/nixos")
    hostProfile
  ];
  boot.kernel.sysctl = {
    # ANSSI R9
    "kernel.dmesg_restrict" = 1;
    "kernel.kptr_restrict" = 2;
    "kernel.pid_max" = 65536;
    "kernel.perf_cpu_time_max_percent" = 1;
    "kernel.perf_event_max_sample_rate" = 1;
    "kernel.perf_event_paranoid" = 2;
    "kernel.unprivileged_bpf_disabled" = 1;
    "kernel.panic_on_oops" = 1;
    # ANSSI R12
    "net.core.bpf_jit_harden" = 2;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.secure_redirects" = 0;
    "net.ipv4.conf.default.secure_redirects" = 0;
    "net.ipv4.conf.all.shared_media" = 0;
    "net.ipv4.conf.default.shared_media" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv4.conf.default.accept_source_route" = 0;
    "net.ipv4.conf.all.arp_filter" = 1;
    "net.ipv4.conf.all.arp_ignore" = 2;
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.icmp_ignore_bogus_error_responses" = 1;
    "net.ipv4.tcp_rfc1337" = 1;
    # ANSSI R14
    "fs.suid_dumpable" = 0;
    "fs.protected_fifos" = 2;
    "fs.protected_regular" = 2;
  };
  # Docker
  virtualisation.docker.enable = true;
  virtualisation.docker.rootless = {
    enable = true;
    setSocketVariable = true;
  };

  # Bootloader.
  boot = {
    kernelParams = [ "intel_iommu=on" "iommu=pt" ];
    kernelPackages = pkgs.linuxPackages_latest;
    plymouth.enable = true;
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    tmp = {
      useTmpfs = false;
      tmpfsSize = "30%";
    };
  };
  networking = {
    hostName = "${hostname}"; # Define your hostname.
    networkmanager.enable = true;
    firewall.enable = false;
  };
  # Set your time zone.
  time.timeZone = "Europe/Paris";
  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "fr_FR.UTF-8";
    LC_IDENTIFICATION = "fr_FR.UTF-8";
    LC_MEASUREMENT = "fr_FR.UTF-8";
    LC_MONETARY = "fr_FR.UTF-8";
    LC_NAME = "fr_FR.UTF-8";
    LC_NUMERIC = "fr_FR.UTF-8";
    LC_PAPER = "fr_FR.UTF-8";
    LC_TELEPHONE = "fr_FR.UTF-8";
    LC_TIME = "fr_FR.UTF-8";
    LC_ALL = "C.UTF-8";
  };
  services = {
    xserver = {
      enable = false;
      xkb.layout = "fr";
      xkb.variant = "oss_latin9";
    };
    printing.enable = true;
    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };
    tailscale.enable = true;
    resolved.enable = true;
  };
  xdg = {
    portal.enable = true;
    portal.wlr.enable = true;
  };

  console.keyMap = "fr";
  hardware = {
    bluetooth.enable = true;
    bluetooth.powerOnBoot = false;
  };
  sound.enable = true;
  hardware.pulseaudio.enable = false;
  security = {
    rtkit.enable = true;
    polkit.enable = true;
    sudo.wheelNeedsPassword = false;
  };
  nixpkgs = {
    config = {
      allowUnfreePredicate = pkg: true;
      allowUnfree = true;
    };
  };
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = false;
    pinentryPackage = pkgs.pinentry-tty;
  };
  programs.ssh.startAgent = true;

  environment.systemPackages = [
    pkgs.gnupg
    pkgs.usbutils
    pkgs.udiskie
    pkgs.udisks
    pkgs.tailscale
    pkgs.update-systemd-resolved
  ];
  environment.variables = { NIXOS_OZONE_WL = "1"; };
  system.stateVersion = "${nixOS_version}";
}
