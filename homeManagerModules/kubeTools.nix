{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules;
  kubeswitchConfig = ''
    kind: SwitchConfig
    version: v1alpha1
    kubeconfigStores:
     - kind: filesystem
       kubeconfigName: "*.kubeconfig"
       paths:
         - ~/.kube/configs
  '';
in {
  options.customHomeManagerModules = {
    kubeTools.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable desktopApps globally or not
      '';
    };
    kubeConfig.didactiklabs.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
      '';
    };
    kubeConfig.bealv.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
      '';
    };
  };
  config = lib.mkIf cfg.kubeTools.enable {
    home = {
      file = {
        ".kube/switch-config.yaml" = {
          text = kubeswitchConfig;
        };
        ".kube/configs/didactiklabs/oidc@didactiklabs.kubeconfig" = lib.mkIf cfg.kubeConfig.didactiklabs.enable {
          source = ../assets/kubeconfigs/oidc-didactiklabs.kubeconfig;
        };
        ".kube/configs/bealv/oidc@bealv.kubeconfig" = lib.mkIf cfg.kubeConfig.bealv.enable {
          source = ../assets/kubeconfigs/oidc-bealv.kubeconfig;
        };
      };
    };
    packages = with pkgs; [
      # clouds
      kubelogin-oidc
      dive
      kcl-cli
      kubectl
      k9s
      kubevirt
      fluxcd
      kind
      kubebuilder
      kubeswitch
      kustomize
    ];
    programs.zsh.initExtra = ''
      source <(switcher init zsh) # kubeswitch
    '';
  };
}
