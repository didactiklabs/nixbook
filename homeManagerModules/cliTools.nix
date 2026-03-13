{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules.cliTools;
in
{
  options.customHomeManagerModules.cliTools = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable CLI utilities and tools
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      # JSON/YAML processing
      jq
      yq-go
      # Archive handling
      unzip
      # System utilities
      wget
      dig
      tree

      # Container inspection
      # Note: dive and skopeo are in kubeTools as they're Kubernetes-related
    ];
  };
}
