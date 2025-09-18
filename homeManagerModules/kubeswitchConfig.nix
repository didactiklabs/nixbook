{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.customHomeManagerModules.kubeswitchConfig;
  sources = import ../npins;

  # Import the kubeswitch module from home-manager master
  kubeswitchModule = import "${sources.home-manager-master}/modules/programs/kubeswitch.nix";
in
{
  imports = [
    kubeswitchModule
  ];

  options.customHomeManagerModules.kubeswitchConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable kubeswitch configuration or not
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.kubeswitch = {
      enable = true;
      commandName = "kswitch";
      enableFishIntegration = config.customHomeManagerModules.fishConfig.enable or false;
      enableZshIntegration = true;
      settings = {
        kind = "SwitchConfig";
        version = "v1alpha1";
        kubeconfigStores = [
          {
            kind = "filesystem";
            kubeconfigName = "*.kubeconfig";
            paths = [ "~/.kube/configs" ];
          }
        ];
      };
    };
  };
}
