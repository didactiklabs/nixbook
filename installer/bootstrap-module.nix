{
  pkgs,
  config,
  lib,
  ...
}:
let
  sources = import ./npins;
  ginx = import ./customPkgs/ginx.nix { inherit pkgs; };
in
{
  imports = [
    ./hardware-configuration.nix
    (sources.disko + "/module.nix")
    ./disko-config.nix
  ];

  # disko-config.nix provides fileSystems, LVM activation, and LUKS setup in initrd
  # hardware-configuration.nix is generated with --no-filesystems to avoid conflicts

  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };
  security.sudo.wheelNeedsPassword = false;

  programs.bash.loginShellInit = ''
    echo "Starting final configuration..."
    sleep 2
    export NIXPKGS_ALLOW_UNFREE=1

     # Regenerate hardware-configuration.nix with fileSystems included
     # base.nix imports /etc/nixos/hardware-configuration.nix and expects fileSystems there
     echo "Regenerating hardware configuration with filesystems..."
     sudo nixos-generate-config --force --root /

     # Now run colmena to apply the final profile
     echo "Applying final configuration via colmena..."
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
        "ata_piix"
        "virtio_pci"
        "virtio_blk"
        "dm_mod"
        "dm_crypt"
        "ext4"
        "xfs"
        "btrfs"
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
