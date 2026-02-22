{
  pkgs,
  lib,
  config,
  ...
}:
{
  imports = [
    ./gitConfig.nix
    ./kanshiConfig.nix
    ./hyprlandConfig.nix
    ./niriConfig.nix
  ];
  home.packages = [
    pkgs.sdl3
    pkgs.moonlight-qt
    pkgs.immich-go
    pkgs.google-chrome
    pkgs.bitwarden-desktop
    pkgs.gitkraken
    (pkgs.google-cloud-sdk.withExtraComponents [
      pkgs.google-cloud-sdk.components.gke-gcloud-auth-plugin
    ])
    pkgs.slack
    pkgs.kanidm_1_8
    pkgs.oapi-codegen
  ];

  profileCustomization = {
  };
  customHomeManagerModules = {
    fontConfig.enable = true;
    gitConfig.enable = true;
    gtkConfig.enable = true;
    sshConfig.enable = true;
    starship.enable = true;
    swayConfig.enable = false;
    hyprlandConfig.enable = false;
    niriConfig.enable = true;
    fastfetchConfig.enable = true;
    desktopApps.enable = true;
    vscode.enable = true;
    kubeTools.enable = true;
    kubeConfig = {
      didactiklabs.enable = true;
      logicmg.enable = true;
    };
    nixvimConfig.enable = true;
    gojiConfig.enable = true;
    atuinConfig.didactiklabs.enable = true;
    kittyConfig.enable = true;
    zshConfig.enable = true;
    kubeswitchConfig.enable = true;
    fcitx5Config.enable = true;
    dmsConfig = {
      enable = true;
      showDock = false;
    };
  };
}
