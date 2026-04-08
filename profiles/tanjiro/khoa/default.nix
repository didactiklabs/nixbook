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
    pkgs.slack
    pkgs.openfortivpn
    pkgs.jira-cli-go
    pkgs.zoom-us
  ];
  programs = {
    go = {
      enable = true;
      env.GOPATH = lib.mkForce "${config.home.homeDirectory}/.local/go";
    };
    zsh = {
      shellAliases = {
        vpn-humboldt = "sudo openfortivpn $(rbw get Humboldt -f url):$(rbw get Humboldt -f port) --username=$(rbw get Humboldt -f username) -p $(rbw get Humboldt)";
      };
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
    thunderbirdConfig.enable = false;
    opencodeConfig.enable = true;
    zenBrowserConfig.enable = true;
    rtk = {
      enable = true;
    };
    dmsConfig = {
      enable = true;
      showDock = true;
    };
    rbwConfig = {
      enable = true;
      email = "vhvictorhang@gmail.com";
      baseUrl = "https://pass.bealv.io";
    };
  };
}
