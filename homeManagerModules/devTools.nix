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
        Whether to enable a curated set of development and DevOps tools.

        Installs:
          Language runtimes:
            - python3

          Build / Nix tooling:
            - gnumake, devenv, nix-eval-jobs, nixos-generators

          Infrastructure-as-Code / deployment:
            - terraform, minio-client
            - google-cloud-sdk (with gke-gcloud-auth-plugin for GKE access)

          Code generation / API:
            - cobra-cli    — Go CLI framework scaffolding
            - openapi-generator-cli — OpenAPI client/server generator
            - templ        — Go HTML templating compiler
            - bruno / bruno-cli — open-source API client (Postman alternative)

          AI assistants:
            - gemini-cli   — Google Gemini CLI
            - claude-code  — Anthropic Claude Code CLI

          Developer utilities:
            - devbox       — portable development environments via Nix
            - go-task      — Makefile alternative (Taskfile)
            - runme        — runnable Markdown notebooks
            - npins        — Nix dependency pinning tool
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
      gemini-cli
      claude-code

      # Development utilities
      devbox
      go-task
      runme
      npins
    ];
  };
}
