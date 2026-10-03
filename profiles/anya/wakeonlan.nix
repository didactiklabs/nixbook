{ pkgs, ... }:
let
  mainIf = "enp34s0";
  mainIfDevice = "sys-subsystem-net-devices-${mainIf}.device";
in
{
  networking.interfaces."${mainIf}".wakeOnLan = {
    enable = true;
    policy = [ "magic" ];
  };
  # A system service: ethtool needs CAP_NET_ADMIN, which a user unit (the old
  # `systemd.user.services` with User=root) can't get, so it failed in a loop.
  # Runs once the NIC exists, after NetworkManager has started.
  systemd.services.wol-custom = {
    description = "Wake-on-lan Hack (module doesn't work).";
    wantedBy = [ "multi-user.target" ];
    bindsTo = [ mainIfDevice ];
    after = [
      mainIfDevice
      "NetworkManager.service"
      "network.target"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.ethtool}/bin/ethtool -s ${mainIf} wol g";
    };
  };
}
