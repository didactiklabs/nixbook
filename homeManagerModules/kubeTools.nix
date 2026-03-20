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
        Whether to enable Kubernetes tools and utilities (kubectl, helm, k9s, kubeswitch, etc.).
      '';
    };
    kubeConfig = {
      didactiklabs.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to enable the didactiklabs OIDC kubeconfig.";
      };
      bealv.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to enable the bealv OIDC kubeconfigs.";
      };
      logicmg.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to enable the logicmg OIDC kubeconfig.";
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
