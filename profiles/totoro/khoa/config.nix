{ pkgs, ... }:
let
  bealvVpnConf = ../../../assets/openvpn/bealv.ovpn;
  sources = import ../../../npins;
  pkgs-unstable = import sources.nixpkgs-unstable { };
in
{
  config = {
    systemd = {
      user = {
        services = {
          bealvVpn = {
            Unit = {
              Description = "Bealv VPN";
              After = [ "default.target" ];
            };
            Install = {
              WantedBy = [ "default.target" ];
            };
            Service = {
              ExecStart = "${pkgs.bash}/bin/bash -c 'sudo -E ${pkgs.openvpn}/bin/openvpn --up ${pkgs.update-systemd-resolved}/libexec/openvpn/update-systemd-resolved --down ${pkgs.update-systemd-resolved}/libexec/openvpn/update-systemd-resolved --config ${bealvVpnConf} --auth-user-pass $HOME/.bealv_vpn_pass --cd /tmp'";
              Restart = "always";
            };
          };
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
          jellyfin-mpv-shim = {
            Unit = {
              Description = "Jellyfin mpv";
            };
            Install = {
              WantedBy = [ "graphical-session.target" ];
            };
            Unit = {
              After = [ "graphical-session.target" ];
            };
            Service = {
              ExecStart = "${pkgs-unstable.jellyfin-mpv-shim}/bin/jellyfin-mpv-shim";
              Restart = "always";
            };
          };
        };
      };
    };
  };
}
