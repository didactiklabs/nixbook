{ pkgs, ... }:
{
  imports = [
    ./gitConfig.nix
    ./sshConfig.nix
    ./kanshiConfig.nix
    ./hyprlandConfig.nix
  ];
  home.packages = [
    # pkgs.jellyfin-mpv-shim
    # pkgs.nextcloud-client
    pkgs.moonlight-qt
    pkgs.google-chrome
    pkgs.mattermost-desktop
    pkgs.bitwarden-desktop
  ];
  profileCustomization = {
    mainWallpaper =
      let
        image = pkgs.fetchurl {
          url = "https://w.wallhaven.cc/full/ym/wallhaven-ymlj6x.jpg";
          sha256 = "sha256-+kAbaZ87j1m6uEeRu1nh5GlGYPlHLl8/KsQyRSFpcQE=";
        };
      in
      "${image}";
    lockWallpaper =
      let
        image = pkgs.fetchurl {
          url = "https://w.wallhaven.cc/full/8x/wallhaven-8xd7vj.jpg";
          sha256 = "sha256-vAiZF7wYbf1CpuAS3gMvwX6KA+D39oJBIt3ffQ8FHVs=";
        };
      in
      "${image}";
  };
  customHomeManagerModules = {
    bluetooth.enable = true;
    fontConfig.enable = true;
    gitConfig.enable = true;
    gtkConfig.enable = true;
    sshConfig.enable = true;
    starship.enable = true;
    swayConfig.enable = false;
    spicetifyConfig.enable = true;
    hyprlandConfig.enable = true;
    # https://github.com/adi1090x/rofi
    rofiConfig = {
      enable = true;
      launcher = {
        type = "type-3";
        style = "style-10";
      };
      powermenu = {
        style = "style-1"; # (1 - 5) # type-1 only
      };
    };
    copyqConfig.enable = true;
    fastfetchConfig.enable = true;
    desktopApps.enable = true;
    kubeTools.enable = true;
    kubeConfig = {
      didactiklabs.enable = true;
      logicmg.enable = true;
    };
    waybar.enable = true;
    nixvimConfig.enable = true;
    gojiConfig.enable = true;
    atuinConfig.didactiklabs.enable = true;
    kittyConfig.enable = true;
  };
}
