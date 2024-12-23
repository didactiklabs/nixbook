{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules;
  homeDir = config.home.homeDirectory;
  didactiklabsPart = lib.optionalString cfg.kubeConfig.didactiklabs.enable ''
    - kind: capi
      config:
        kubeconfigPath: '${homeDir}/.kube/configs/didactiklabs/oidc@didactiklabs.kubeconfig'
  '';
  kubeswitch = pkgs.kubeswitch.overrideAttrs (old: {
    version = "master";
    src = pkgs.fetchFromGitHub {
      owner = "danielfoehrKn";
      repo = "kubeswitch";
      rev = "master";
      hash = "sha256-IQwGMa2q29r8Jn5e5ApngefBgksIQlf9Hut0CHn/yiU=";
    };
  });
  kubeswitchConfig =
    ''
      kind: SwitchConfig
      version: v1alpha1
      kubeconfigStores:
      - kind: filesystem
        kubeconfigName: "*.kubeconfig"
        paths:
        - ~/.kube/configs
    ''
    + didactiklabsPart;
  sources = import ../npins;
  pkgs-unstable = import sources.nixpkgs-unstable { };
  kl = import ../customPkgs/kl.nix { inherit pkgs; };
in
{
  options.customHomeManagerModules = {
    kubeTools.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable desktopApps globally or not
      '';
    };
    kubeConfig = {
      didactiklabs.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "";
      };
      bealv.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "";
      };
      logicmg.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "";
      };
    };
  };
  config = lib.mkIf cfg.kubeTools.enable {
    home = {
      file = {
        ".kube/switch-config.yaml" = {
          text = kubeswitchConfig;
        };
        ".kube/configs/didactiklabs/oidc@didactiklabs.kubeconfig" =
          lib.mkIf cfg.kubeConfig.didactiklabs.enable
            { source = ../assets/kubeconfigs/oidc-didactiklabs.kubeconfig; };
        ".kube/configs/bealv/oidc@bealv.kubeconfig" = lib.mkIf cfg.kubeConfig.bealv.enable {
          source = ../assets/kubeconfigs/oidc-bealv.kubeconfig;
        };
        ".kube/configs/logicmg/oidc@logicmg.kubeconfig" = lib.mkIf cfg.kubeConfig.logicmg.enable {
          source = ../assets/kubeconfigs/oidc-logicmg.kubeconfig;
        };
      };
      packages = with pkgs; [
        # clouds
        kl
        kubectl-neat
        kubelogin-oidc
        dive
        pkgs-unstable.kcl
        pkgs-unstable.netfetch
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
      ];
    };
    programs.zsh = {
      initExtra = ''
        source <(switcher init zsh) # kubeswitch
      '';
      shellAliases = {
        k = "kubectl";
        pctl = "cli";
      };
    };
  };
}
