{ config, pkgs, lib, ... }:
let
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
  sources = import ../npins;
  kclRepo = sources.kcl-nix;
  kcl = pkgs.callPackage "${kclRepo}/kcl.nix" { };
in {
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
        ".kube/switch-config.yaml" = { text = kubeswitchConfig; };
        ".kube/configs/didactiklabs/oidc@didactiklabs.kubeconfig" =
          lib.mkIf cfg.kubeConfig.didactiklabs.enable {
            source = ../assets/kubeconfigs/oidc-didactiklabs.kubeconfig;
          };
        ".kube/configs/bealv/oidc@bealv.kubeconfig" =
          lib.mkIf cfg.kubeConfig.bealv.enable {
            source = ../assets/kubeconfigs/oidc-bealv.kubeconfig;
          };
        ".kube/configs/logicmg/oidc@logicmg.kubeconfig" =
          lib.mkIf cfg.kubeConfig.logicmg.enable {
            source = ../assets/kubeconfigs/oidc-logicmg.kubeconfig;
          };
      };
      packages = with pkgs; [
        # clouds
        kubelogin-oidc
        dive
        # kcl-cli
        kubectl
        k9s
        kubevirt
        fluxcd
        kubebuilder
        kubeswitch
        kustomize
        kcl
      ];
    };
    programs.zsh.initExtra = ''
      source <(switcher init zsh) # kubeswitch
    '';
  };
}
