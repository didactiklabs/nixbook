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
    ./hyprlandConfig.nix
  ];
  home.packages = [
    pkgs.jellyfin-mpv-shim
    pkgs.nextcloud-client
    pkgs.moonlight-qt
  ];
  profileCustomization = {
    mainWallpaper = let
      image = pkgs.fetchurl {
        url = "https://w.wallhaven.cc/full/r7/wallhaven-r7937j.jpg";
        sha256 = "sha256-ts6lsP/IrGtiP/AgIMGFbyLlJ/yAS8WaSnIHTyv+Bdc=";
      };
    in "${image}";
    lockWallpaper = let
      image = pkgs.fetchurl {
        url = "https://w.wallhaven.cc/full/48/wallhaven-48m6ky.jpg";
        sha256 = "sha256-XzwhvsTYITK3etpFYG5xAhnbNwX0ewe7iz0XeVpuSrI=";
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
    };
    copyqConfig.enable = true;
    fastfetchConfig.enable = true;
    desktopApps.enable = true;
    kubeTools.enable = true;
    waybar.enable = true;
    nixvimConfig.enable = true;
  };
}
