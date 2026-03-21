{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules;
  kl = import ../customPkgs/kl.nix { inherit pkgs; };
  songbird = import ../customPkgs/songbird.nix { inherit pkgs; };
  pvmigrate = import ../customPkgs/pvmigrate.nix { inherit pkgs; };
  crd-wizard = import ../customPkgs/crd-wizard.nix { inherit pkgs; };
in
{
  options.customHomeManagerModules = {
    kubeTools.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable the full Kubernetes toolchain.

        Installs a comprehensive set of Kubernetes CLI tools and utilities:
          Core:
            - kubectl           — Kubernetes CLI
            - kubernetes-helm   — Helm package manager
            - k9s               — TUI cluster dashboard (config in k9sConfig.nix)
            - kubeswitch        — multi-kubeconfig context switcher (kswitch alias)
            - kubelogin-oidc    — OIDC authentication plugin for kubectl
            - kustomize         — Kubernetes overlay management

          Inspection & debugging:
            - kubectl-neat      — strip noisy fields from kubectl YAML output
            - kubectl-view-secret — base64-decode secrets in-place
            - kubectl-explore   — interactive resource browser
            - skopeo            — inspect/copy container images without pulling
            - dive              — explore container image layers
            - netfetch          — network debugging tool
            - kubevirt          — virtctl for KubeVirt VMs (SSH, console)
            - fluxcd            — Flux GitOps CLI (flux)

          Custom packages:
            - kl        — opinionated multi-pod log viewer
            - songbird  — custom cluster management utility
            - pvmigrate — Proxmox VM migration tool
            - crd-wizard — CRD visualisation dashboard (Shift-E in k9s)
            - sou       — container image analysis wrapper

          Others:
            - kubebuilder — Kubernetes controller scaffolding
            - kind        — local Kubernetes clusters via Docker
            - paralus-cli — Paralus zero-trust access CLI

        Also sets:
          - k=kubectl shell alias
          - pctl=cli shell alias
          - kubectl and songbird Zsh completions

        See also: kubeConfig.* options for OIDC kubeconfig file deployment,
        and k9sConfig.nix for k9s settings and plugins.
      '';
    };
    kubeConfig = {
      didactiklabs.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to deploy the DidactikLabs OIDC kubeconfig.

          Copies assets/kubeconfigs/oidc-didactiklabs.kubeconfig to
          ~/.kube/configs/didactiklabs/oidc@didactiklabs.kubeconfig so
          kubeswitch can discover it automatically.
        '';
      };
      bealv.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to deploy the Bealv OIDC kubeconfigs (prod + non-prod).

          Copies two kubeconfigs to ~/.kube/configs/bealv/:
            - oidc@bealv.kubeconfig      (non-production cluster)
            - oidc@bealvprod.kubeconfig  (production cluster)
        '';
      };
      logicmg.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to deploy the LogicMG OIDC kubeconfig.

          Copies assets/kubeconfigs/oidc-logicmg.kubeconfig to
          ~/.kube/configs/logicmg/oidc@logicmg.kubeconfig.

          Used on: nishinoya (aamoyel's machine).
        '';
      };
    };
  };
  config = lib.mkIf cfg.kubeTools.enable {
    home = {
      file = {
        ".kube/configs/didactiklabs/oidc@didactiklabs.kubeconfig" =
          lib.mkIf cfg.kubeConfig.didactiklabs.enable
            { source = ../assets/kubeconfigs/oidc-didactiklabs.kubeconfig; };
        ".kube/configs/bealv/oidc@bealv.kubeconfig" = lib.mkIf cfg.kubeConfig.bealv.enable {
          source = ../assets/kubeconfigs/oidc-bealv.kubeconfig;
        };
        ".kube/configs/bealv/oidc@bealvprod.kubeconfig" = lib.mkIf cfg.kubeConfig.bealv.enable {
          source = ../assets/kubeconfigs/oidc-bealvprod.kubeconfig;
        };
        ".kube/configs/logicmg/oidc@logicmg.kubeconfig" = lib.mkIf cfg.kubeConfig.logicmg.enable {
          source = ../assets/kubeconfigs/oidc-logicmg.kubeconfig;
        };
      };
      packages = with pkgs; [
        # clouds
        songbird
        kl
        pvmigrate
        skopeo
        kubectl-neat
        kubelogin-oidc
        dive
        netfetch
        kubectl
        k9s
        kubevirt
        fluxcd
        kubeswitch
        kubebuilder
        kustomize
        kubectl-view-secret
        kubectl-explore
        paralus-cli
        crd-wizard
        # Kubernetes package managers
        kubernetes-helm
        kind
        sou
      ];
    };
    programs = {
      zsh = {
        initContent = ''
          source <(songbird completion zsh)
          source <(kubectl completion zsh)
        '';
        shellAliases = {
          k = "kubectl";
          pctl = "cli";
        };
      };
    };
  };
}
