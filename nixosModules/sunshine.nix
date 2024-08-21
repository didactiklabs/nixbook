{ config, pkgs, lib, ... }:
let cfg = config.customNixOSModules.sunshine;
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
    systemd.user.services.sunshine = {
      description = "Sunshine Gamestreaming server.";
      partOf = [ "graphical-session.target" ];
      requires = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.sunshine}/bin/sunshine";
        Restart = "always";
      };
    };
    security.wrappers.sunshine = {
      owner = "root";
      group = "root";
      capabilities = "cap_sys_admin+p";
      source = "${pkgs.sunshine}/bin/sunshine";
    };
  };
}
