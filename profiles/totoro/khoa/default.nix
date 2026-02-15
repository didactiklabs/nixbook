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
    ./config.nix
    ./hyprlandConfig.nix
    ./niriConfig.nix
  ];
  home.packages = [
    pkgs-unstable.claude-code
    pkgs-unstable.sdl3
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
    # https://github.com/adi1090x/rofi
    rofiConfig.enable = false;
    copyqConfig.enable = false;
    fastfetchConfig.enable = true;
    desktopApps.enable = true;
    swayncConfig.enable = false;
    kubeTools.enable = true;
    kubeConfig.didactiklabs.enable = true;
    kubeConfig.bealv.enable = true;
    waybarConfig.enable = false;
    nixvimConfig.enable = true;
    gojiConfig.enable = true;
    atuinConfig.didactiklabs.enable = true;
    kittyConfig.enable = true;
    zshConfig.enable = true;
    kubeswitchConfig.enable = true;
    fcitx5Config.enable = true;
    dmsConfig.enable = true;
  };
}
