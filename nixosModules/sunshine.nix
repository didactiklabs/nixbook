{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customNixOSModules.sunshine;
in
{
  options.customNixOSModules.sunshine = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable the Sunshine game-streaming / remote-desktop server.

        Sunshine is an open-source implementation of the NVIDIA GameStream
        protocol, compatible with Moonlight clients on any device.

        This module:
        - Runs sunshine as a user systemd service tied to the graphical session
          target (starts/stops with the desktop session, restarts on crash)
        - Wraps the sunshine binary with cap_sys_admin capability so it can
          capture the display and audio without running as root
        - The web UI is available at https://localhost:47990 after first launch
          to pair with Moonlight clients

        Used on: anya (gaming/streaming machine).
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
        # The capability wrapper below, not the bare binary: without
        # cap_sys_admin Sunshine can't use KMS capture.
        ExecStart = "${config.security.wrapperDir}/sunshine";
        Restart = "always";
        # Not the 100 ms default: a port clash or a missing display would
        # hit the start limit in a second and leave the unit failed.
        RestartSec = "5s";
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
