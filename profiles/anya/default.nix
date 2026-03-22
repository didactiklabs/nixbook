{
  pkgs,
  lib,
  sources,
  ...
}:
let
  overrides = {
    customHomeManagerModules = { };
    imports = [ ./fastfetchConfig.nix ];
  };
  userConfig = import ../../nixosModules/userConfig.nix {
    inherit
      lib
      pkgs
      sources
      overrides
      ;
  };
in
{
  systemd.user = {
    services = {
      steamBigPicture = {
        enable = true;
        description = "SteamBigPicture";
        partOf = [ "graphical-session.target" ];
        requires = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        wantedBy = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.steam}/bin/steam steam://open/bigpicture";
          Restart = "always";
        };
      };
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
    gamingConfig.enable = true;
    sunshine.enable = true;
    sway.enable = true;
    caCertificates = {
      bealv.enable = true;
      didactiklabs.enable = true;
    };
  };
  nix = {
    settings = {
      trusted-users = [
        "root"
        "@wheel"
      ];
    };
  };
  imports = [
    ./immich.nix
    ./wakeonlan.nix
    (userConfig.mkUser {
      username = "khoa";
      userImports = [ ./khoa ];
    })
    # ./kubernetes.nix
  ];
}
