{
  config,
  pkgs,
  lib,
  sources,
  ...
}:
let
  cfg = config.customNixOSModules;
  ds4drv = pkgs.python313Packages.ds4drv.overrideAttrs (oldAttrs: {
    src = sources.ds4drv;
  });
  ginx = import ../customPkgs/ginx.nix { inherit pkgs; };
  osupdate = pkgs.writeShellScriptBin "osupdate" ''
    set -euo pipefail
    echo last applied revisions: $(${pkgs.jq}/bin/jq .rev /etc/nixos/version)
    echo applying revision: "$(${pkgs.git}/bin/git ls-remote https://github.com/didactiklabs/nixbook HEAD | awk '{print $1}')"...

    echo Running ginx...
    ${ginx}/bin/ginx --source https://github.com/didactiklabs/nixbook -b main --now -- ${pkgs.sudo}/bin/sudo ${pkgs.colmena}/bin/colmena apply-local
  '';
in
{
  options.customNixOSModules.tools = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to enable the tools NixOS module.
        Provides podman, yubikey tools, ds4 controller support, and system utilities.
      '';
    };
  };

  config = lib.mkIf cfg.tools.enable {
    virtualisation = {
      oci-containers.backend = "podman";
      podman = {
        enable = true;
        # Create a `docker` alias for podman, to use it as a drop-in replacement
        dockerCompat = true;
        # Required for containers under podman-compose to be able to talk to each other.
        defaultNetwork.settings.dns_enabled = true;
        autoPrune = {
          enable = true;
          dates = "weekly";
        };
      };
    };
    boot = {
      kernelModules = [
        "ip6_tables"
        "ip6table_nat"
        "ip_tables"
        "iptable_nat"
        "nf_conntrack"
        "nf_conntrack_ipv4"
        "ip_vs"
        "ip_vs_rr"
        "ip_vs_wrr"
        "ip_vs_sh"
      ];
    };

    # System packages - Core utilities only
    # User-level packages should be in homeManagerModules (devTools, securityTools, systemTools, cliTools)
    environment.systemPackages = with pkgs; [
      openvpn
      podman
      podman-compose
      # GPG and SSH
      gnupg
      # Yubikey tools
      yubico-piv-tool
      yubico-pam
      yubioath-flutter
      yubikey-personalization
      accountsservice
      wlsunset
      cups-pk-helper
      ginx
      osupdate
      ds4drv
      efibootmgr
      colmena
      update-systemd-resolved
      pinentry-qt
      lsof
    ];

    services.udev = {
      packages = with pkgs; [
        game-devices-udev-rules
        yubikey-personalization
      ];
      extraRules = ''
        KERNEL=="uinput", MODE="0666"
        KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="05c4", MODE="0666"
        KERNEL=="hidraw*", SUBSYSTEM=="hidraw", KERNELS=="0005:054C:05C4.*", MODE="0666"
        KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="09cc", MODE="0666"
        KERNEL=="hidraw*", SUBSYSTEM=="hidraw", KERNELS=="0005:054C:09CC.*", MODE="0666"
      '';
    };

    systemd.user.services.ds4drv = {
      enable = true;
      description = "Controller Support.";
      wantedBy = [ "default.target" ];
      serviceConfig = {
        ExecStart = "${ds4drv}/bin/ds4drv --hidraw --emulate-xpad";
        Restart = "always";
      };
    };

    programs = {
      kdeconnect.enable = true;
      yubikey-touch-detector.enable = true;
      gnupg.agent = {
        enable = true;
        enableSSHSupport = true; # yubikey ssh
        pinentryPackage = pkgs.pinentry-qt;
      };
    };
  };
}
