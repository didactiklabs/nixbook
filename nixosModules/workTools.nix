{
  config,
  pkgs,
  pkgs-unstable,
  lib,
  ...
}:
let
  cfg = config.customNixOSModules;
in
{
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
    # workTools
    environment = {
      systemPackages =
        (with pkgs; [
          cobra-cli
          minio-client
          python3
          nix-eval-jobs
          terraform
          dig
          jq
          yq-go
          tig
          unzip
          gnumake
          templ
          tree
          openvpn
          nixos-generators
          podman
          podman-compose
          google-cloud-sdk
          openapi-generator-cli
          bruno
          bruno-cli
        ])
        ++ (with pkgs-unstable; [
          kind
          sou
        ]);
    };
  };
}
