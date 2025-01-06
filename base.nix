{
  config,
  hostname,
  lib,
  ...
}:
let
  sources = import ./npins;
  pkgs = import sources.nixpkgs {
    config = {
      allowUnfree = true;
      allowUnfreePredicate = true;
    };
  };
  pkgs-unstable = import sources.nixpkgs-unstable {
    config = {
      allowUnfree = true;
      allowUnfreePredicate = true;
    };
  };
  hostProfile = import ./profiles/${hostname} {
    inherit
      lib
      config
      pkgs
      pkgs-unstable
      hostname
      sources
      ;
  };
  ginx = import ./customPkgs/ginx.nix { inherit pkgs; };
  osupdate = pkgs.writeShellScriptBin "osupdate" ''
    set -euo pipefail
    echo last applied revisions: $(${pkgs.jq}/bin/jq .rev /etc/nixos/version)
    echo applying revision: "$(${pkgs.git}/bin/git ls-remote https://github.com/didactiklabs/nixbook HEAD | awk '{print $1}')"...

    echo Running ginx...
    ${ginx}/bin/ginx --source https://github.com/didactiklabs/nixbook -b main --now -- ${pkgs.colmena}/bin/colmena apply-local --sudo
  '';
  jsonFile = builtins.toJSON {
    url = builtins.readFile (
      pkgs.runCommand "getRemoteUrl" { buildInputs = [ pkgs.git ]; } ''
        if [ -d ${./.git} ]; then
          grep -oP '(?<=url = ).*' ${./.git/config} | tr -d '\n' > $out;
        else
          echo "no remote URL" | tr -d '\n' > $out;
        fi
      ''
    );
    branch = builtins.readFile (
      pkgs.runCommand "getBranch" { buildInputs = [ pkgs.git ]; } ''
        if [ -d ${./.git} ]; then
          cat ${./.git/HEAD} | awk '{print $2}' | tr -d '\n' > $out;
        else
          echo "unknown" | tr -d '\n' > $out;
        fi
      ''
    );
    rev =
      if builtins.pathExists ./.git then
        let
          gitRepo = builtins.fetchGit ./.; # Fetch the Git repository
        in
        gitRepo.rev # Access the 'rev' attribute directly
      else
        {
          rev = "unknown"; # Default value when there's no .git directory
        }
        .rev;
    lastModifiedDate =
      if builtins.pathExists ./.git then
        let
          gitRepo = builtins.fetchGit ./.; # Fetch the Git repository
        in
        gitRepo.lastModifiedDate
      else
        {
          lastModifiedDate = "unknown";
        }
        .lastModifiedDate;
  };
in
{
  environment = {
    etc = {
      "nixos/version".source = pkgs.writeText "projectGit.json" jsonFile;
    };
    systemPackages = with pkgs; [
      # global
      ginx
      osupdate
      efibootmgr
      colmena
      npins
      tailscale
      update-systemd-resolved
      gnupg
      pinentry-tty
      # usb mount auto
      usbutils
      udiskie
      udisks
      # yubikey
      yubico-piv-tool
      yubico-pam
      yubioath-flutter
      yubikey-personalization
      yubikey-manager-qt
    ];
    variables = {
      NIXOS_OZONE_WL = "1";
    };
  };
  imports = [
    /etc/nixos/hardware-configuration.nix
    ./nixosModules/caCertificates.nix
    ./nixosModules/laptopProfile.nix
    ./nixosModules/greetd.nix
    ./nixosModules/sway.nix
    ./nixosModules/hyprland.nix
    ./nixosModules/printTools.nix
    ./nixosModules/workTools.nix
    ./nixosModules/tailscale-fix.nix
    (import ./nixosModules/networkManager.nix { inherit lib config pkgs; })
    (import ./nixosModules/sunshine.nix { inherit lib config pkgs; })
    (import "${sources.home-manager}/nixos")
    hostProfile
  ];
  # Bootloader.
  boot = {
    kernelModules = [
      "uinput"
      "usbhid"
    ];
    kernel = {
      sysctl = {
        "kernel.dmesg_restrict" = 1;
        "kernel.kptr_restrict" = 2;
        "kernel.pid_max" = 65536;
        "kernel.perf_cpu_time_max_percent" = 1;
        "kernel.perf_event_max_sample_rate" = 1;
        "kernel.perf_event_paranoid" = 2;
        "kernel.unprivileged_bpf_disabled" = 1;
        "kernel.panic_on_oops" = 1;
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
        "fs.suid_dumpable" = 0;
        "fs.protected_fifos" = 2;
        "fs.protected_regular" = 2;
      };
    };
    tmp.cleanOnBoot = true;
    kernelParams = [
      "intel_iommu=on"
      "iommu=pt"
    ];
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
    pcscd.enable = true; # yubikey smart card mode
    udev = {
      packages = with pkgs; [
        game-devices-udev-rules
        yubikey-personalization
      ];
    };
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
        ExecStart = "${pkgs.python312Packages.ds4drv}/bin/ds4drv --hidraw --emulate-xpad";
        Restart = "always";
      };
    };
  };
  security = {
    rtkit.enable = true;
    polkit.enable = true;
    sudo.wheelNeedsPassword = false;
    pam = {
      services = {
        # yubikey login
        login.u2fAuth = true;
        sudo.u2fAuth = true;
      };
      u2f = {
        enable = true;
      };
    };
  };
  nixpkgs.config.allowUnfree = true;
  nix = {
    package = pkgs.lix;
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
      trusted-users = [
        "root"
        "@wheel"
      ];
      nix-path = [
        "nixpkgs=${sources.nixpkgs}"
        "home-manager=${sources.home-manager}"
      ];
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      substituters = [ "https://s3.didactiklabs.io/nix-cache" ];
      trusted-public-keys = [
        "didactiklabs-nixcache:PxLKN0+ZkP07M8g8/B6xbP6A4MYpqQg6LH7V3muiy/0="
      ];
    };
    extraOptions = ''
      # Ensure we can still build when missing-server is not accessible
      fallback = true
    '';
  };
  programs = {
    yubikey-touch-detector.enable = true;
    gnupg.agent = {
      enable = true;
      enableSSHSupport = true; # yubikey ssh
      pinentryPackage = pkgs.pinentry-tty;
    };
  };
  system.stateVersion = "24.05";
}
