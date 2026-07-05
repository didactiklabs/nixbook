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
          ExecStart = "/run/current-system/sw/bin/steam steam://open/bigpicture";
          Restart = "always";
        };
      };
    };
  };
  # Disable all forms of sleep/suspend/hibernate
  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    hybrid-sleep.enable = false;
  };
  services = {
    greetd = {
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
    logind.settings.Login = {
      IdleAction = "ignore";
      IdleActionSec = 0;
    };
    openssh.enable = true;
  };
  # anya bypasses customNixOSModules.greetd (manual autologin above), so wire
  # up the keyring PAM session module here. With a passwordless autologin PAM
  # cannot unlock the keyring — it only auto-starts the daemon with its control
  # socket. For fully silent operation the "login" keyring password must be
  # blank (set once via seahorse); otherwise the gcr prompter (enabled globally
  # in core.nix) asks on first Secret Service use.
  security.pam.services.greetd.enableGnomeKeyring = true;
  customNixOSModules = {
    gamingConfig.enable = true;
    gamingConfig.gpu = "amd";
    simracing.enable = true;
    sunshine.enable = true;
    wolf = {
      enable = true;
      hostAppsStateFolder = "/data/wolf";
    };
    ollama.enable = true;
    sway.enable = true;
    tailscale.enable = false;
    netbird-tools.enable = false;
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
