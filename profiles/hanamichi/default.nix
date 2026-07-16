{
  pkgs,
  lib,
  sources,
  config,
  ...
}:
let
  overrides = {
    customHomeManagerModules = { };
    imports = [ ];
  };
  userConfig = import ../../nixosModules/userConfig.nix {
    inherit
      lib
      pkgs
      sources
      overrides
      ;
  };
in
{
  # --- Boot loader: keep only a few generations ---
  # The ESP (/boot, sdb1) is a 200M partition shared with Windows on this
  # dual-boot disk and cannot be grown without moving the Windows partitions.
  # Cap NixOS generations so kernels + initrds fit alongside the Windows boot
  # files (overrides the shared default of 10 in nixosModules/core.nix).
  boot.loader.systemd-boot.configurationLimit = lib.mkForce 2;

  # --- Disable all sleep / suspend ---
  systemd.sleep.settings.Sleep = {
    AllowSuspend = "no";
    AllowHibernation = "no";
    AllowHybridSleep = "no";
    AllowSuspendThenHibernate = "no";
  };
  services = {
    logind.settings.Login = {
      IdleAction = "ignore";
      IdleActionSec = "infinity";
    };
    xserver.xkb = {
      layout = lib.mkForce "us";
      variant = lib.mkForce "";
    };

    # --- NVIDIA RTX 3080 (Ampere) proprietary driver ---
    xserver.videoDrivers = [ "nvidia" ];
  };

  # --- US keyboard layout (overrides the shared French default) ---
  console.keyMap = lib.mkForce "us";
  hardware = {
    bluetooth = {
      powerOnBoot = lib.mkForce true;
    };
    nvidia = {
      # Required for most Wayland compositors (niri included).
      modesetting.enable = true;
      # Use the open-source kernel modules (recommended for Ampere / RTX 3080).
      open = true;
      # nvidia-settings control panel.
      nvidiaSettings = true;
      # Production driver branch from the configured nixpkgs.
      package = config.boot.kernelPackages.nvidiaPackages.production;
      # Power management is generally unneeded on a desktop and can cause
      # resume issues; keep it off.
      powerManagement.enable = false;
      powerManagement.finegrained = false;
    };
  };

  customNixOSModules = {
    # Login: tuigreet greeter offering the niri session (totoro pattern).
    greetd.enable = true;
    niri.enable = true;
    hyprland.enable = false;
    sway.enable = false;
    # Gaming stack (Steam, Proton, GameMode, 32-bit graphics) without the
    # AMD-specific GPU tuning.
    gamingConfig.enable = true;
    gamingConfig.gpu = "nvidia";
    # Sim racing hardware support (Moza & Fanatec wheelbases, pedals, etc.).
    simracing.enable = true;
    # Printing & scanning (CUPS, ipp-usb, Avahi mDNS discovery, SANE airscan).
    printTools.enable = true;
    lanzaboote.enable = false;
    # System-level support for the Lotus Vietnamese input method (the fcitx5
    # addon is enabled in the user's Home Manager fcitx5Config: lotus = true).
    fcitx5-lotus = {
      enable = true;
      users = [ "chocomooncake" ];
    };
  };

  imports = [
    (userConfig.mkUser {
      username = "chocomooncake";
      userImports = [ ./chocomooncake ];
      shell = pkgs.zsh;
    })
  ];
}
