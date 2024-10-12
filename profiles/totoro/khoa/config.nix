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
              WantedBy = [ "graphical-session.target" ];
            };
            Unit = {
              After = [ "graphical-session.target" ];
            };
            Service = {
              ExecStart = "${pkgs.nextcloud-client}/bin/nextcloud";
              Restart = "always";
            };
          };
          bealvVpn = {
            Unit = {
              Description = "Bealv VPN";
              After = [ "graphical-session.target" ];
            };
            Install = {
              WantedBy = [ "graphical-session.target" ];
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
