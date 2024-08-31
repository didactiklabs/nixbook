{ config, hostname, lib, ... }:
let
  sources = import ./npins;
  pkgs = import sources.nixpkgs { config = { allowUnfree = true; }; };
  pkgs-unstable =
    import sources.nixpkgs-unstable { config = { allowUnfree = true; }; };
  inherit (sources) lix-module lix;
  hostProfile = import ./profiles/${hostname} {
    inherit lib config pkgs pkgs-unstable hostname sources;
  };
in {
  imports = [
    ./hardware-configuration.nix
    ./nixosModules/caCertificates.nix
    ./nixosModules/laptopProfile.nix
    ./nixosModules/greetd.nix
    ./nixosModules/sway.nix
    ./nixosModules/hyprland.nix
    ./nixosModules/printTools.nix
    ./nixosModules/workTools.nix
    (import ./nixosModules/networkManager.nix { inherit lib config pkgs; })
    (import ./nixosModules/sunshine.nix { inherit lib config pkgs; })
    (import "${sources.home-manager}/nixos")
    (import "${lix-module}/module.nix" { inherit lix; })
    hostProfile
  ];
  # Bootloader.
  boot = {
    kernelModules = [ "uinput" ];
    kernel = {
      sysctl = {
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
    };
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
  console.keyMap = "fr";
  services = {
    udev = { packages = with pkgs; [ game-devices-udev-rules ]; };
    xserver = {
      enable = false;
      xkb.layout = "fr";
      xkb.variant = "oss_latin9";
    };
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
  hardware = {
    bluetooth = {
      enable = true;
      powerOnBoot = false;
      package = pkgs.bluez;
    };
    pulseaudio.enable = false;
    uinput.enable = true;
  };
  systemd = {
    # Create a separate slice for nix-daemon that is
    # memory-managed by the userspace systemd-oomd killer
    slices."nix-daemon".sliceConfig = {
      ManagedOOMMemoryPressure = "kill";
      ManagedOOMMemoryPressureLimit = "50%";
    };
    services."nix-daemon".serviceConfig.Slice = "nix-daemon.slice";
    # If a kernel-level OOM event does occur anyway,
    # strongly prefer killing nix-daemon child processes
    services."nix-daemon".serviceConfig.OOMScoreAdjust = 1000;
    user.services.ds4drv = {
      enable = true;
      description = "Controller Support.";
      wantedBy = [ "default.target" ];
      serviceConfig = {
        ExecStart =
          "${pkgs.python312Packages.ds4drv}/bin/ds4drv --hidraw --emulate-xpad";
        Restart = "always";
      };
    };
  };
  # sound.enable = true;
  security = {
    rtkit.enable = true;
    polkit.enable = true;
    sudo.wheelNeedsPassword = false;
  };
  nixpkgs = {
    config = {
      allowUnfreePredicate = _: true;
      allowUnfree = true;
    };
  };
  nix = {
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
    optimise = {
      automatic = true;
      dates = [ "03:45" ];
    };
    settings = {
      nix-path =
        [ "nixpkgs=${sources.nixpkgs}" "home-manager=${sources.home-manager}" ];
      experimental-features = [ "nix-command" "flakes" ];
    };
  };
  programs = {
    gnupg.agent = {
      enable = true;
      enableSSHSupport = false;
      pinentryPackage = pkgs.pinentry-tty;
    };
    ssh.startAgent = true;
  };
  environment = {
    systemPackages = with pkgs; [
      npins
      tailscale
      update-systemd-resolved
      gnupg
      pinentry-tty
      usbutils
      udiskie
      udisks
    ];
    variables = {
      NIXOS_OZONE_WL = "1";
      WINEDLLOVERRIDES = "version,dxgi=n,b";
    };
  };
  system.stateVersion = "24.05";
}
