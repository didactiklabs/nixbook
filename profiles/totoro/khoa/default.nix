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
    ./config.nix
    ./hyprlandConfig.nix
    ./niriConfig.nix
    ./thunderbirdConfig.nix
  ];
  home.packages = [
    pkgs.claude-code
    pkgs.sdl3
    pkgs.moonlight-qt
    pkgs.jellyfin-media-player
  ];
  programs = {
    go = {
      enable = true;
      env.GOPATH = lib.mkForce "${config.home.homeDirectory}/.local/go";
    };
  };

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
    kubeTools.enable = true;
    kubeConfig.didactiklabs.enable = true;
    kubeConfig.bealv.enable = true;
    nixvimConfig.enable = true;
    gojiConfig.enable = true;
    atuinConfig.didactiklabs.enable = true;
    kittyConfig.enable = true;
    zshConfig.enable = true;
    kubeswitchConfig.enable = true;
    fcitx5Config.enable = true;
    thunderbirdConfig.enable = true;
    dmsConfig = {
      enable = true;
      showDock = true;
    };
  };
}
