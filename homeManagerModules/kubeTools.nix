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
  options.customHomeManagerModules.kubeTools = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable desktopApps globally or not
      '';
    };
  };
  config = lib.mkIf cfg.kubeTools.enable {
    home.packages = with pkgs; [
      # clouds
      kcl-cli
      kubectl
      k9s
      kubevirt
      fluxcd
      kind
      kubebuilder
      kubeswitch
    ];
    home.file.".kube/switch-config.yaml" = {
      text = kubeswitchConfig;
    };
    programs.zsh.initExtra = ''
      source <(switcher init zsh) # kubeswitch
    '';
  };
}
