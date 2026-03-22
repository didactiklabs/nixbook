{ pkgs, ... }:
let
  mainIf = "enp34s0";
in
{
  networking.interfaces."${mainIf}".wakeOnLan = {
    enable = true;
    policy = [ "magic" ];
  };
  systemd.user.services.wol-custom = {
    enable = true;
    description = "Wake-on-lan Hack (module doesn't work).";
    partOf = [ "default.target" ];
    requires = [ "default.target" ];
    after = [ "default.target" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      User = "root";
      Group = "root";
      ExecStart = "${pkgs.ethtool}/bin/ethtool -s ${mainIf} wol g";
      Restart = "always";
    };
  };
}
