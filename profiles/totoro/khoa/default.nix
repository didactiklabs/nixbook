{pkgs, ...}: {
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
        url = "https://images8.alphacoders.com/136/1363709.png";
        sha256 = "sha256-MMZxInaiOSkzO3f77RUS1Ol4BVGBO2HZGwF6jZI697Q=";
      };
    in "${image}";
    lockWallpaper = let
      image = pkgs.fetchurl {
        url = "https://w.wallhaven.cc/full/z8/wallhaven-z8y7jo.png";
        sha256 = "sha256-wRtvsEFggeEjJj/mf1TsrDAIXcc0+Ot8DkTcUCGWemY=";
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
    swayConfig.enable = false;
    hyprlandConfig.enable = true;
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
    kubeConfig.didactiklabs.enable = true;
    waybar.enable = true;
    nixvimConfig.enable = true;
  };
}
