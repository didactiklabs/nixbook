{
  pkgs,
  config,
  lib,
  ...
}:
let
  sources = import ./npins;
  ginx = import ./customPkgs/ginx.nix { inherit pkgs; };
  diskoConfig = if builtins.pathExists ./disko-config.nix then ./disko-config.nix else null;
in
{
  imports = [
    ./hardware-configuration.nix
    (sources.disko + "/module.nix")
  ]
  ++ (if diskoConfig != null then [ diskoConfig ] else [ ]);

  # Disko provides fileSystems and boot.initrd.luks.devices from disko-config.nix

  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };
  security.sudo.wheelNeedsPassword = false;

  programs.bash.loginShellInit = ''
    echo "Starting final configuration..."
    sleep 2
    export NIXPKGS_ALLOW_UNFREE=1

    # IMPORTANT: Regenerate hardware-configuration.nix BEFORE running colmena
    # The final profile (base.nix) imports /etc/nixos/hardware-configuration.nix
    # which must contain fileSystems for the system to boot properly.
    # This must happen before colmena apply since colmena builds the final config.
    echo "Regenerating hardware configuration with filesystems..."
    sudo rm -rf /etc/nixos/hardware-configuration.nix
    sudo nixos-generate-config --root /

    # Now run colmena to apply the final profile
    # The hardware-configuration.nix now contains proper fileSystems
    ginx --source https://github.com/didactiklabs/nixbook -b main --now -- colmena apply-local --sudo

    sleep 10
    sudo reboot
  '';

  nixpkgs.config.allowUnfree = true;
  environment.systemPackages = with pkgs; [
    wpa_supplicant
    wirelesstools
    networkmanager
    dhcpcd
    ginx
    colmena
    git
  ];

  services.getty.autologinUser = "nixos";

  networking = {
    useDHCP = true;
  };
  networking.dhcpcd.enable = true;

  boot = {
    initrd = {
      # Ensure necessary kernel modules are available in initrd for disk access
      availableKernelModules = [
        "nvme"
        "xhci_pci"
        "ahci"
        "usb_storage"
        "sd_mod"
      ];
    };
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
  };

  hardware.enableRedistributableFirmware = true;

  nix = {
    package = pkgs.lix;
    settings = {
      trusted-users = [
        "root"
        "@wheel"
      ];
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      substituters = [ "https://s3.didactiklabs.io/nix-cache" ];
      trusted-public-keys = [ "didactiklabs-nixcache:PxLKN0+ZkP07M8g8/B6xbP6A4MYpqQg6LH7V3muiy/0=" ];
    };
    extraOptions = "fallback = true";
  };
}
