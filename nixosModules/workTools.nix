{
  config,
  pkgs,
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
    # workTools - System-level packages only
    # User-level packages should be in homeManagerModules (devTools, cliTools, kubeTools, gitConfig)
    environment = {
      systemPackages = with pkgs; [
        opencode
        openvpn
        podman
        podman-compose
      ];
    };
  };
}
