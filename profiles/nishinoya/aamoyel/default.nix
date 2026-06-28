{
  pkgs,
  lib,
  config,
  ...
}:
let
  moonfin = import ../../../customPkgs/moonfin.nix { inherit pkgs; };
in
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
    pkgs.gitkraken
    pkgs.slack
    pkgs.kanidm_1_9
    pkgs.oapi-codegen
    pkgs.spotify
    moonfin
  ];

  xdg.mimeApps.defaultApplications = {
    "text/html" = "google-chrome.desktop";
    "x-scheme-handler/http" = "google-chrome.desktop";
    "x-scheme-handler/https" = "google-chrome.desktop";
  };

  customHomeManagerModules = {
    cliTools.enable = true;
    devTools.enable = true;
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
      rpcu.enable = true;
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
    moonfinConfig.enable = true;
  };
  services.kdeconnect.enable = true;
}
