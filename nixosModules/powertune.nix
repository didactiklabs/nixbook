{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.customNixOSModules;
  powertune = pkgs.writeShellScriptBin "powertune" ''
    #!/bin/bash
    ${pkgs.powertop}/bin/powertop --auto-tune
    HIDDEVICES=$(ls /sys/bus/usb/drivers/usbhid | grep -oE '^[0-9]+-[0-9\.]+' | sort -u)
    for i in $HIDDEVICES; do
      echo -n "Enabling " | cat - /sys/bus/usb/devices/$i/product
      echo 'on' > /sys/bus/usb/devices/$i/power/control
    done
  '';
in {
  config = lib.mkIf cfg.powertune.enable {
    environment.systemPackages = [
      powertune
      pkgs.powertop
    ];
    systemd.services.powertune = {
      description = "Powertune.";
      wantedBy = ["default.target"];
      serviceConfig = {
        ExecStart = "${powertune}/bin/powertune";
        Restart = "always";
      };
    };
  };

  options.customNixOSModules.powertune = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable powertune config globally or not.
      '';
    };
  };
}
