{
  pkgs,
  lib,
  config,
  ...
}:
let
  sources = import ../../../npins;
  pkgs-unstable = import sources.nixpkgs-unstable { };
in
{
  imports = [
    ./gitConfig.nix
    ./kanshiConfig.nix
    ./hyprlandConfig.nix
  ];
  home.packages = [
    pkgs-unstable.sdl3
    pkgs.moonlight-qt
    pkgs-unstable.immich-go
    pkgs.google-chrome
    pkgs.bitwarden-desktop
    pkgs-unstable.gitkraken
    (pkgs.google-cloud-sdk.withExtraComponents [
      pkgs.google-cloud-sdk.components.gke-gcloud-auth-plugin
    ])
    pkgs.slack
    pkgs-unstable.kanidm_1_8
    pkgs-unstable.oapi-codegen
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
    # https://github.com/adi1090x/rofi
    rofiConfig.enable = false;
    copyqConfig.enable = false;
    fastfetchConfig.enable = true;
    desktopApps.enable = true;
    swayncConfig.enable = false;
    kubeTools.enable = true;
    kubeConfig = {
      didactiklabs.enable = true;
      logicmg.enable = true;
    };
    waybarConfig.enable = false;
    nixvimConfig.enable = true;
    gojiConfig.enable = true;
    atuinConfig.didactiklabs.enable = true;
    kittyConfig.enable = true;
    zshConfig.enable = true;
    kubeswitchConfig.enable = true;
    fcitx5Config.enable = true;
    dmsConfig.enable = true;
    dmsConfig.showDock = false;
    dmsConfig.nixosUpdate.enable = true;
  };
}
