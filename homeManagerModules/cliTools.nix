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
        Whether to enable essential CLI utilities for day-to-day shell work.

        Installs lightweight, focused command-line tools:
          - jq        — JSON processor / query language
          - yq-go     — YAML/TOML/XML processor (jq-compatible syntax)
          - unzip     — ZIP archive extraction
          - wget      — HTTP/FTP file downloader
          - dig       — DNS query tool (from bind-tools)
          - tree      — Recursive directory listing

        This module is intentionally minimal: container-inspection tools (dive,
        skopeo) live in kubeTools, and richer shell integrations live in
        zshConfig / commonShellConfig.
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
