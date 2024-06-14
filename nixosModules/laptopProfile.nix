{
  config,
  pkgs,
  lib,
  ...
}: let
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
    services.power-profiles-daemon.enable = false;
    services.fwupd.enable = true;
    services.thermald.enable = true;
    hardware = {
      enableAllFirmware = true;
      enableRedistributableFirmware = true;
      cpu.intel.updateMicrocode = true;
    };
    powerManagement = lib.mkForce {
      enable = true;
      powertop.enable = false; # to false else, it will shut your mouse down too often
      #cpuFreqGovernor = lib.mkDefault "powersave";
      #cpuFreqGovernor = lib.mkDefault "ondemand";
    };
    # https://github.com/AdnanHodzic/auto-cpufreq
    #services.auto-cpufreq.enable = true;
    ## https://linrunner.de/tlp/settings/index.html
    services.tlp = lib.mkForce {
      enable = true;
      settings = {
        ## https://linrunner.de/tlp/settings/processor.html
        PCIE_ASPM_ON_BAT = "powersupersave";
        CPU_ENERGY_PERF_POLICY_ON_BAT = "balance_power";
        CPU_ENERGY_PERF_POLICY_ON_AC = "balance_power";

        CPU_BOOST_ON_AC = 0;
        CPU_BOOST_ON_BAT = 0;

        CPU_MAX_PERF_ON_BAT = 60;
        CPU_MAX_PERF_ON_AC = 80;

        #CPU_SCALING_GOVERNOR_ON_AC = "performance";
        CPU_SCALING_GOVERNOR_ON_AC = "powersave";
        CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
        START_CHARGE_THRESH_BAT0 = 20;
        STOP_CHARGE_THRESH_BAT0 = 80;
      };
    };
    #services.upower.enable = true;
    environment.systemPackages = [
      pkgs.powertop
      pkgs.upower
    ];
  };
}
