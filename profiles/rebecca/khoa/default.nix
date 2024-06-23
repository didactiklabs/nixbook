{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules;
in {
  imports = [
    ./gitConfig.nix
    ./kanshiConfig.nix
    ./config.nix
  ];
  home.packages = [
    pkgs.jellyfin-mpv-shim
    pkgs.nextcloud-client
    pkgs.moonlight-qt
  ];
  profileCustomization = {
    mainWallpaper = let
      image = pkgs.fetchurl {
        url = "https://w.wallhaven.cc/full/6d/wallhaven-6d65zq.jpg";
        sha256 = "sha256-1lB28nl2jqki1xXI7nmuw2kVQ5jYxmDuLPagJ6dCUdQ=";
      };
    in "${image}";
    lockWallpaper = let
      image = pkgs.fetchurl {
        url = "https://w.wallhaven.cc/full/6o/wallhaven-6okd5l.png";
        sha256 = "sha256-uofSasQgDYmvuS7ZQJxY1oLht0X4o/Sq0ZrHACh01AQ=";
      };
    in "${image}";
  };
  customHomeManagerModules = {
    bluetooth.enable = true;
    fontConfig.enable = true;
    gitConfig.enable = true;
    gtkConfig.enable = true;
    sshConfig.enable = true;
    starship.enable = true;
    swayConfig.enable = true;
    hyprlandConfig.enable = true;
    vim.enable = true;
    stylixConfig.enable = true;
    # https://github.com/adi1090x/rofi
    rofiConfig = {
      enable = true;
      launcher = {
        type = "type-3";
        style = "style-10";
      };
      powermenu = {
        style = "style-1"; #(1 - 5) # type-1 only
      };
      color = "dracula";
    };
    copyqConfig.enable = true;
    fastfetchConfig.enable = true;
    desktopApps.enable = true;
    kubeTools.enable = true;
    waybar.enable = true;
  };
}
