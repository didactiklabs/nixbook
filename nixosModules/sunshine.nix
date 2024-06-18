{
  config,
  pkgs,
  lib,
  username,
  ...
}: let
  cfg = config.customNixOSModules.sunshine;
in {
  options.customNixOSModules.sunshine = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable sunshine globally or not
      '';
    };
  };
  config = lib.mkIf cfg.enable {
    programs.steam = {
      enable = true;
    };
    boot.kernelModules = ["uinput"];
    security.wrappers.sunshine = {
      owner = "root";
      group = "root";
      capabilities = "cap_sys_admin+p";
      source = "${pkgs.sunshine}/bin/sunshine";
    };
    users.users."${username}" = {
      extraGroups = ["input"];
    };
  };
}
