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
  ];

  # hardware-configuration.nix provides fileSystems detected from the disko-formatted disk

  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };
  security.sudo.wheelNeedsPassword = false;

  programs.bash.loginShellInit = ''
    echo "Starting final configuration..."
    sleep 2
    export NIXPKGS_ALLOW_UNFREE=1

    # CRITICAL: The hardware-configuration.nix must exist with proper fileSystems
    # before any configuration rebuild. This is used by the bootloader.
    echo "Regenerating hardware configuration with filesystems..."

    # Ensure disko-config.nix is still available for imports
    if [ ! -f /etc/nixos/disko-config.nix ]; then
      echo "ERROR: disko-config.nix not found. Cannot proceed without disk configuration."
      exit 1
    fi

    # Remove old hardware config so nixos-generate-config regenerates it
    sudo rm -rf /etc/nixos/hardware-configuration.nix

    # Generate hardware configuration - this will detect filesystems from disko
    sudo nixos-generate-config --root /

    # Verify fileSystems were detected
    if ! grep -q "fileSystems" /etc/nixos/hardware-configuration.nix; then
      echo "ERROR: No fileSystems found in generated hardware-configuration.nix"
      cat /etc/nixos/hardware-configuration.nix
      exit 1
    fi

    # Now run colmena to apply the final profile
    # The hardware-configuration.nix now contains proper fileSystems
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
