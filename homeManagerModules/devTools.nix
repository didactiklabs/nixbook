{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules.devTools;
in
{
  options.customHomeManagerModules.devTools = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable development tools
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      # Language runtimes
      python3

      # Build tools
      gnumake
      devenv
      nix-eval-jobs
      nixos-generators

      # IaC and deployment
      terraform
      minio-client
      (google-cloud-sdk.withExtraComponents [
        google-cloud-sdk.components.gke-gcloud-auth-plugin
      ])

      # API and code generation
      cobra-cli
      openapi-generator-cli
      templ

      # API clients
      bruno
      bruno-cli

      # AI assistants
      opencode
      gemini-cli

      # Development utilities
      devbox
      go-task
      runme
      npins
    ];
  };
}
