{
  pkgs,
  lib,
  sources,
  ...
}:
let
  mainIf = "enp34s0";
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
  immichServer = "photos.didactiklabs.io";
  cyberPicturePath = "$HOME/.steam/steam/steamapps/compatdata/1091500/pfx/drive_c/users/steamuser/Pictures/Cyberpunk 2077";
  tw3PicturePath = "$HOME/.steam/steam/steamapps/compatdata/292030/pfx/drive_c/users/steamuser/Documents/The Witcher 3/screenshots";
in
{
  ## wake with sunshine
  networking.interfaces."${mainIf}".wakeOnLan = {
    enable = true;
    policy = [ "magic" ];
  };
  systemd.user = {
    services = {
      immich-tw3 = {
        description = "Run my command";
        serviceConfig = {
          ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.immich-go}/bin/immich-go upload from-folder --no-ui --api-key $(${pkgs.coreutils}/bin/cat $HOME/.immich-token) --server https://${immichServer} --into-album Gaming \"${tw3PicturePath}/\" && ${pkgs.coreutils}/bin/rm -fr \"${tw3PicturePath}/*\"'";
        };
      };
      immich-cyberpunk = {
        description = "Run my command";
        serviceConfig = {
          ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.immich-go}/bin/immich-go upload from-folder --no-ui --api-key $(${pkgs.coreutils}/bin/cat $HOME/.immich-token) --server https://${immichServer} --into-album Gaming \"${cyberPicturePath}/\" && ${pkgs.coreutils}/bin/rm -fr \"${cyberPicturePath}/*\"'";
        };
      };
      wol-custom = {
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
    timers = {
      immich-tw3-timer = {
        enable = true;
        description = "Timer to run myService every 5 minutes for tw3";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnUnitActiveSec = "5min";
          Persistent = true;
          Unit = "immich-tw3.service";
        };
      };
      immich-cyberpunk-timer = {
        enable = true;
        description = "Timer to run myService every 5 minutes for CP2077";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnUnitActiveSec = "5min";
          Persistent = true;
          Unit = "immich-cyberpunk.service";
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
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    extraCompatPackages = with pkgs; [ proton-ge-bin ];
    extest.enable = true;
  };
  hardware.steam-hardware.enable = true;
  services.openssh.enable = true;
  customNixOSModules = {
    networkManager.enable = true;
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
    (userConfig.mkUser {
      username = "khoa";
      userImports = [ ./khoa ];
    })
    # ./kubernetes.nix
  ];
}
