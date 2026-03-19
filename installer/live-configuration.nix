{
  pkgs,
  modulesPath,
  config,
  lib,
  ...
}:
{
  image.fileName = lib.mkForce "${config.image.isoBaseName}-${config.system.nixos.label}-${pkgs.stdenv.hostPlatform.system}-interactive.iso";
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    ./installer.nix
  ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "ahci"
    "usb_storage"
    "uas"
    "sd_mod"
    "thunderbolt"
  ];
  hardware.enableAllFirmware = true;

  services.getty.autologinUser = "nixos";
  console.keyMap = "fr";
  networking = {
    hostName = "";
    useDHCP = lib.mkForce true; # Ensures this value takes precedence
  };
  environment.systemPackages = [
    pkgs.hwinfo
    pkgs.busybox
    pkgs.gum
  ]
  ++ (with config.system.build.scripts; [
    installer
  ]);
  nix = {
    package = pkgs.lix;
    settings = {
      trusted-users = [
        "root"
        "@wheel"
      ];
      substituters = [ "https://s3.didactiklabs.io/nix-cache" ];
      trusted-public-keys = [ "didactiklabs-nixcache:PxLKN0+ZkP07M8g8/B6xbP6A4MYpqQg6LH7V3muiy/0=" ];
    };
    extraOptions = ''
      # Ensure we can still build when missing-server is not accessible
      fallback = true
    '';
  };
  programs.bash.loginShellInit = ''
    clear
    sudo ${config.system.build.scripts.installer}/bin/installer
  '';
}
