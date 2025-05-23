{
  config,
  pkgs,
  lib,
  ...
}:
let
  powertune = pkgs.writeShellScriptBin "powertune" ''
    #!/bin/bash
    ${pkgs.powertop}/bin/powertop --auto-tune
    HIDDEVICES=$(ls /sys/bus/usb/drivers/usbhid | grep -oE '^[0-9]+-[0-9\.]+' | sort -u)
    for i in $HIDDEVICES; do
      echo -n "Enabling " | cat - /sys/bus/usb/devices/$i/product
      echo 'on' > /sys/bus/usb/devices/$i/power/control
    done
  '';
  cfg = config.customNixOSModules.laptopProfile;
in
{
  options.customNixOSModules.laptopProfile = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable laptopProfile globally or not
      '';
    };
  };
  config = lib.mkIf cfg.enable {
    ## not sure why i have to enforce it to false :shrug:
    services = {
      tlp = {
        enable = true;
        settings = {
          SOUND_POWER_SAVE_ON_BAT = 1;
          SOUND_POWER_SAVE_ON_AC = 0;
          START_CHARGE_THRESH_BAT0 = 75;
          STOP_CHARGE_THRESH_BAT0 = 80;
          START_CHARGE_THRESH_BAT1 = 75;
          STOP_CHARGE_THRESH_BAT1 = 80;
          START_CHARGE_THRESH_BATT = 75;
          STOP_CHARGE_THRESH_BATT = 80;
          RESTORE_THRESHOLDS_ON_BAT = 1;
        };
      };
      power-profiles-daemon.enable = false;
      fwupd.enable = true;
      thermald.enable = true;
    };
    hardware = {
      enableAllFirmware = true;
      enableRedistributableFirmware = true;
      cpu.intel.updateMicrocode = true;
    };
    powerManagement = lib.mkForce {
      enable = true;
      powertop.enable = false; # to false else, it will shut your mouse down too often
    };
    # https://github.com/AdnanHodzic/auto-cpufreq
    services.auto-cpufreq.enable = true;
    services.auto-cpufreq.settings = {
      battery = {
        governor = "powersave";
        min_freq = "400MHz"; # Set if you know your CPU's capabilities
        max_freq = "2GHz"; # Set if you know your CPU's capabilities
        turbo = "never";
        energy_performance_preference = "power";
      };
      charger = {
        governor = "performance";
        turbo = "auto";
        # https://github.com/AdnanHodzic/auto-cpufreq/issues/661#issuecomment-2063197922
        energy_performance_preference = "performance";
      };
    };
    # systemd.services.powertune = {
    #   description = "Powertune.";
    #   wantedBy = [ "default.target" ];
    #   serviceConfig = {
    #     ExecStart = "${powertune}/bin/powertune";
    #     Restart = "on-failure";
    #   };
    # };
    environment.systemPackages = [
      powertune
      pkgs.powertop
    ];
  };
}
