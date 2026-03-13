{
  pkgs,
  config,
  ...
}:
let
  sources = import ./npins;
  ginx = import ./customPkgs/ginx.nix { inherit pkgs; };
  # Detect if disko config exists and import it
  diskoConfig = if builtins.pathExists ./disko-config.nix then ./disko-config.nix else null;
in
{
  imports = [
    ./hardware-configuration.nix
    (sources.disko + "/module.nix")
  ]
  ++ (if diskoConfig != null then [ diskoConfig ] else [ ]);

  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };
  security.sudo.wheelNeedsPassword = false;

  programs.bash.loginShellInit = ''
    echo "Starting final configuration..."
    sleep 2
    export NIXPKGS_ALLOW_UNFREE=1
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
      # Copy LUKS password file into initrd so it can be used during boot
      secrets = {
        "/secrets/luks-pass" = "/etc/nixos/secrets/luks-pass";
      };
    };
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
  };

  # Note: LUKS configuration is handled automatically by disko module
  # when disko-config.nix contains luks partitions
  # The password file is copied into the initrd via boot.initrd.secrets above

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
