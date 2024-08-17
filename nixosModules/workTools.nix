{ config, pkgs, lib, ... }:
let cfg = config.customNixOSModules;
in {
  options.customNixOSModules.workTools = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable workTools globally or not.
      '';
    };
  };
  config = lib.mkIf cfg.workTools.enable {
    # Podman
    virtualisation = {
      oci-containers.backend = "podman";
      podman = {
        enable = true;
        # Create a `docker` alias for podman, to use it as a drop-in replacement
        dockerCompat = true;
        # Required for containers under podman-compose to be able to talk to each other.
        defaultNetwork.settings.dns_enabled = true;
      };
    };
    # workTools
    environment = {
      systemPackages = with pkgs; [
        python3
        nix-eval-jobs
        dig
        jq
        yq-go
        tig
        unzip
        go
        gnumake
        templ
        tree
        openvpn
        nixos-generators
        gnome.simple-scan
        podman
        podman-compose
        google-cloud-sdk
      ];
    };
  };
}
