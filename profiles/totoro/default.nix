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
  tailscale-fix-routes = pkgs.writeShellScriptBin "tailscale-fix-routes" ''
    set -euo pipefail
    SUBNET=$(ip -4 route show default | awk '{print $3}' | cut -d. -f1-3).0/16
    ip monitor route | while read -r line; do
        if echo "$line" | grep -q "$SUBNET dev tailscale0"; then
            if ip route show table 52 | grep -q "$SUBNET dev tailscale0"; then
                ip route del $SUBNET dev tailscale0 table 52
            fi
        fi
    done
  '';
in
{
  environment = {
    systemPackages = [
      tailscale-fix-routes
    ];
  };
  systemd = {
    services.tailscale-fix-routes = {
      enable = true;
      path = [
        pkgs.iproute2
        pkgs.busybox
      ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${tailscale-fix-routes}/bin/tailscale-fix-routes";
        Restart = "always";
      };
    };
  };
  networking.hosts = {
    "100.111.17.126" = [
      "gitea"
      "git.s3ns.internal"
    ];
    "10.254.0.5" = [
      "frieren"
    ];
    "10.207.7.1" = [
      "anya"
    ];
    "10.207.7.2" = [
      "gojo"
    ];
  };
  # services.udev.extraRules = ''
  #   ACTION=="remove",\
  #    ENV{PRODUCT}=="1050/406/571",\
  #    RUN+="${pkgs.systemd}/bin/loginctl lock-sessions"
  #   ACTION=="remove",\
  #    ENV{PRODUCT}=="1050/402/543",\
  #    RUN+="${pkgs.systemd}/bin/loginctl lock-sessions"
  # '';
  customNixOSModules = {
    workTools.enable = true;
    laptopProfile.enable = true;
    networkManager.enable = true;
    greetd.enable = true;
    hyprland.enable = true;
    caCertificates = {
      bealv.enable = true;
      didactiklabs.enable = true;
    };
  };
  imports = [
    (userConfig.mkUser {
      username = "khoa";
      userImports = [ ./khoa ];
    })
  ];
}
