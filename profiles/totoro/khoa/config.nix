{ pkgs, ... }:
let
  bealvVpnConf = ../../../assets/openvpn/bealv.ovpn;
in
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
          jellyfin-mpv-shim = {
            Unit = {
              Description = "Jellyfin mpv";
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
              ExecStart = "${pkgs.jellyfin-mpv-shim}/bin/jellyfin-mpv-shim";
              Restart = "always";
            };
          };
          bealvVpn = {
            Unit = {
              Description = "Bealv VPN";
              After = [
                "graphical-session.target"
                "network-online.target"
              ];
            };
            Install = {
              WantedBy = [
                "graphical-session.target"
                "network-online.target"
              ];
            };
            Service = {
              ExecStart = "${pkgs.bash}/bin/bash -c 'sudo -E ${pkgs.openvpn}/bin/openvpn --up ${pkgs.update-systemd-resolved}/libexec/openvpn/update-systemd-resolved --down ${pkgs.update-systemd-resolved}/libexec/openvpn/update-systemd-resolved --config ${bealvVpnConf} --auth-user-pass $HOME/.bealv_vpn_pass --cd /tmp'";
              Restart = "always";
            };
          };
        };
      };
    };
  };
}
