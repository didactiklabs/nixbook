{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.customHomeManagerModules.kubeswitchConfig;
in
{
  options.customHomeManagerModules.kubeswitchConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable kubeswitch context-switcher configuration.

        kubeswitch (exposed as the `kswitch` command) is a terminal UI and CLI
        for switching between multiple kubeconfigs / contexts stored across
        many files.  This replaces the traditional KUBECONFIG env-var juggling.

        Configuration:
          - commandName: kswitch (aliased as `ks` in the shell)
          - Zsh integration enabled (shell function injection)
          - Fish integration enabled when fishConfig is active
          - Store: filesystem, scanning ~/.kube/configs/** for files matching *.*
            (picks up all kubeconfigs deployed by the kubeConfig.*.enable options)
          - Kind: SwitchConfig v1alpha1

        Requires kubeTools.enable = true to have the kubeswitch binary available.
        Used on: totoro, nishinoya.
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
            kubeconfigName = "*.*";
            paths = [ "~/.kube/configs" ];
          }
        ];
      };
    };
  };
}
