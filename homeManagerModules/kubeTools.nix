{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules;
  # homeDir = config.home.homeDirectory;
  # didactiklabsPart = lib.optionalString cfg.kubeConfig.didactiklabs.enable ''
  #   - kind: capi
  #     config:
  #       kubeconfigPath: '${homeDir}/.kube/configs/didactiklabs/oidc@didactiklabs.kubeconfig'
  # '';
  # kubeswitch = pkgs.kubeswitch.overrideAttrs (old: {
  #   src = sources.kubeswitch;
  # });
  # k9s = pkgs.k9s.overrideAttrs (oldAttrs: {
  #   src = sources.k9s;
  #   vendorHash = "sha256-MOTDKPo433YU9mYg9olKSvbLqjIgmXI91593c1zXMVU=";
  # });

  sources = import ../npins;
  pkgs-unstable = import sources.nixpkgs-unstable { };
  kl = import ../customPkgs/kl.nix { inherit pkgs; };
  songbird = import ../customPkgs/songbird.nix { inherit pkgs; };
  pvmigrate = import ../customPkgs/pvmigrate.nix { inherit pkgs; };
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
      fish = lib.mkIf (config.customHomeManagerModules.fishConfig.enable or false) {
        shellInit = ''
          songbird completion fish | source
        '';
        shellAliases = {
          k = "kubectl";
          pctl = "cli";
        };
      };
    };
  };
}
