{ pkgs, lib, sources, ... }:
let
  mainIf = "enp34s0";
  overrides = {
    customHomeManagerModules = { };
    imports = [ ./fastfetchConfig.nix ];
  };
  userConfig = import ../../nixosModules/userConfig.nix {
    inherit lib pkgs sources;
    overrides = overrides;
  };
  mkUser = userConfig.mkUser;
in {
  ## wake with sunshine
  networking.interfaces."${mainIf}".wakeOnLan = {
    enable = true;
    policy = [ "magic" ];
  };
  systemd.services.wol-custom = {
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
  services.greetd = {
    # force start with my user, no greeter/login
    enable = true;
    settings = rec {
      initial_session = {
        command = "${pkgs.swayfx}/bin/sway";
        user = "khoa";
      };
      default_session = initial_session;
    };
  };
  services.openssh.enable = true;
  customNixOSModules = {
    laptopProfile.enable = true;
    networkManager.enable = true;
    sunshine.enable = true;
    sway.enable = true;
  };
  imports = [
    (mkUser {
      username = "khoa";
      userImports = [ ./khoa ];
    })
  ];
}
