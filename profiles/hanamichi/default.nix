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
  # --- NVIDIA RTX 3080 (Ampere) proprietary driver ---
  services.xserver.videoDrivers = [ "nvidia" ];
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
    lanzaboote.enable = false;
  };

  imports = [
    (userConfig.mkUser {
      username = "chocomooncake";
      userImports = [ ./chocomooncake ];
      shell = pkgs.zsh;
    })
  ];
}
