{ pkgs, ... }:
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

  # First boot: disko-config.nix provides fileSystems, LVM activation, and LUKS in initrd
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

    # Regenerate hardware-configuration.nix WITH fileSystems for the final config
    # nixos-generate-config detects current hardware and mounted filesystems
    # base.nix expects fileSystems in this file
    echo "Regenerating hardware configuration..."
    sudo nixos-generate-config --force

    # Inject LUKS configuration because nixos-generate-config doesn't detect LVM-on-LUKS.
    # It only checks the direct dm UUID of filesystem devices but LVM sits between
    # the filesystem and the LUKS container, so the LUKS layer is invisible to it.
    echo "Checking for LUKS devices..."
    if [ -b /dev/mapper/crypted ]; then
      echo "Found /dev/mapper/crypted, extracting backing device..."
      LUKS_BACKING_DEV=$(sudo ${pkgs.cryptsetup}/bin/cryptsetup status crypted | ${pkgs.gawk}/bin/awk '/device:/ {print $2}')
      echo "LUKS backing device: $LUKS_BACKING_DEV"
      if [ -n "$LUKS_BACKING_DEV" ]; then
        LUKS_UUID=$(sudo ${pkgs.util-linux}/bin/blkid -s UUID -o value "$LUKS_BACKING_DEV")
        echo "LUKS partition UUID: $LUKS_UUID"
        if [ -n "$LUKS_UUID" ]; then
          echo "Injecting LUKS configuration into hardware-configuration.nix..."
          # Remove the closing brace, append LUKS config, re-close
          sudo ${pkgs.gnused}/bin/sed -i '/^}$/d' /etc/nixos/hardware-configuration.nix
          echo '  boot.initrd.luks.devices."crypted".device = "/dev/disk/by-uuid/'"$LUKS_UUID"'";' | sudo tee -a /etc/nixos/hardware-configuration.nix >/dev/null
          echo '}' | sudo tee -a /etc/nixos/hardware-configuration.nix >/dev/null
        else
          echo "WARNING: Could not determine LUKS UUID!"
        fi
      else
        echo "WARNING: Could not determine LUKS backing device!"
      fi
    else
      echo "No LUKS device found (no /dev/mapper/crypted), skipping LUKS injection."
    fi

    echo "=== Generated hardware-configuration.nix ==="
    cat /etc/nixos/hardware-configuration.nix
    echo "============================================="
    sleep 5

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
    cryptsetup
    util-linux
  ];

  services.getty.autologinUser = "nixos";
  networking = {
    useDHCP = true;
    dhcpcd.enable = true;
  };

  boot = {
    initrd = {
      availableKernelModules = [
        "nvme"
        "xhci_pci"
        "ahci"
        "usb_storage"
        "sd_mod"
        "ata_piix"
        "virtio_pci"
        "virtio_blk"
      ];
    };
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
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
