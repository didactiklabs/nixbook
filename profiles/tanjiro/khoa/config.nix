{ pkgs, ... }:
{
  config = {
    systemd = {
      user = {
        services = {
          nextcloud-client = {
            Unit = {
              Description = "Nextcloud";
            };
            Install = {
              WantedBy = [
                "graphical-session.target"
                "network-online.target"
              ];
            };
            Unit = {
              After = [
                "graphical-session.target"
                "network-online.target"
              ];
            };
            Service = {
              ExecStart = "${pkgs.nextcloud-client}/bin/nextcloud";
              Restart = "always";
            };
          };
        };
      };
    };
  };
}
