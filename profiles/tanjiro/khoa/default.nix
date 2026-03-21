{
  pkgs,
  lib,
  config,
  ...
}:
{
  imports = [
    ../../totoro/khoa/gitConfig.nix
    ../../totoro/khoa/niriConfig.nix
    ./niriConfig.nix
    ../../totoro/khoa/thunderbirdConfig.nix
  ];
  home.packages = [
  ];
  programs = {
    go = {
      enable = true;
      env.GOPATH = lib.mkForce "${config.home.homeDirectory}/.local/go";
    };
  };
  customHomeManagerModules = {
    cliTools.enable = true;
    devTools.enable = true;
    fontConfig.enable = true;
    gitConfig.enable = true;
    gtkConfig.enable = true;
    sshConfig.enable = true;
    starship.enable = true;
    niriConfig.enable = true;
    fastfetchConfig.enable = true;
    desktopApps.enable = true;
    kubeTools.enable = true;
    nixvimConfig.enable = true;
    gojiConfig.enable = true;
    atuinConfig.didactiklabs.enable = true;
    kittyConfig.enable = true;
    zshConfig.enable = true;
    kubeswitchConfig.enable = true;
    thunderbirdConfig.enable = true;
    opencodeConfig.enable = true;
    rtk = {
      enable = true;
    };
    dmsConfig = {
      enable = true;
      showDock = true;
    };
  };
}
