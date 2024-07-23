{ config, pkgs, lib, ... }:
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
in {
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
      powertop.enable =
        false; # to false else, it will shut your mouse down too often
    };
    # https://github.com/AdnanHodzic/auto-cpufreq
    services.auto-cpufreq.enable = true;
    services.auto-cpufreq.settings = {
      battery = {
        governor = "powersave";
        turbo = "never";
      };
      charger = {
        governor = "performance";
        turbo = "auto";
      };
    };
    systemd.services.powertune = {
      description = "Powertune.";
      wantedBy = [ "default.target" ];
      serviceConfig = {
        ExecStart = "${powertune}/bin/powertune";
        Restart = "always";
      };
    };
    environment.systemPackages = [ powertune pkgs.powertop ];
  };
}
