{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules.devTools;
  inherit (pkgs.customPkgs) openchoreo-cli opencode-manager;
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
            - antigravity-cli (`agy`) — Google's agent CLI (successor of gemini-cli,
              which nixpkgs is removing)
            - claude-code  — Anthropic Claude Code CLI

          Developer utilities:
            - devbox       — portable development environments via Nix
            - go-task      — Makefile alternative (Taskfile)
            - runme        — runnable Markdown notebooks
            - npins        — Nix dependency pinning tool
            - openchoreo-cli — OpenChoreo internal developer platform CLI (occ)
            - opencode-manager (`ocm`) — k9s-style TUI to manage isolated
              OpenCode workspaces in containers; seeds the built-in module
              catalogue into ~/.config/opencode-manager/modules on activation
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
      opentofu
      ansible
      minio-client
      (google-cloud-sdk.withExtraComponents [
        google-cloud-sdk.components.gke-gcloud-auth-plugin
      ])
      openstackclient
      openstack-rs
      yaookctl

      # API and code generation
      cobra-cli
      openapi-generator-cli
      templ

      # API clients
      bruno
      bruno-cli

      # AI assistants
      antigravity-cli
      claude-code

      # Development utilities
      git-crypt
      devbox
      go-task
      runme
      npins
      openchoreo-cli
      opencode-manager
    ];

    # Seed the built-in module catalogue the way the npm postinstall does:
    # copy it into ~/.config/opencode-manager/modules, replacing built-in
    # modules (so upgrades take effect) while leaving user-authored ones in
    # place. Guarded by a stamp with the store path, so unrelated switches
    # never clobber local module edits.
    home.activation.opencodeManagerModules = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      modulesDir="$HOME/.config/opencode-manager/modules"
      stamp="$modulesDir/.nix-store"
      if [ "$(cat "$stamp" 2>/dev/null)" != "${opencode-manager}" ]; then
        $DRY_RUN_CMD mkdir -p "$modulesDir"
        for category in ${opencode-manager}/share/opencode-manager/modules/*; do
          name="''${category##*/}"
          $DRY_RUN_CMD mkdir -p "$modulesDir/$name"
          for module in "$category"/*; do
            mod="''${module##*/}"
            $DRY_RUN_CMD rm -rf "$modulesDir/$name/$mod"
            $DRY_RUN_CMD cp -R "$module" "$modulesDir/$name/$mod"
            $DRY_RUN_CMD chmod -R u+w "$modulesDir/$name/$mod"
          done
        done
        if [ -z "$DRY_RUN_CMD" ]; then
          printf '%s' "${opencode-manager}" > "$stamp"
        fi
      fi
    '';
  };
}
