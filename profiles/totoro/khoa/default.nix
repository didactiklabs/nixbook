{
  pkgs,
  lib,
  ...
}:
{
  imports = [
    ./gitConfig.nix
    ./kanshiConfig.nix
    ./config.nix
    ./hyprlandConfig.nix
  ];
  home.packages = [
    pkgs.moonlight-qt
    pkgs.ankama-launcher
  ];
  programs.go = {
    enable = true;
    goPath = lib.mkForce ".local/go";
  };

  profileCustomization = {
    mainWallpaper =
      let
        image = pkgs.fetchurl {
          url = "https://i.imgur.com/RnshrNY.jpeg";
          sha256 = "sha256-ExW9AS3LrsxzqdRzME5a5Nqa3qKmNtUsKayYxj+8+1g=";
        };
      in
      "${image}";
    lockWallpaper =
      let
        image = pkgs.fetchurl {
          url = "https://w.wallhaven.cc/full/g7/wallhaven-g71w1e.jpg";
          sha256 = "sha256-L2MWwr70Zcz9+M1XpRhWMxhhNF0iscghOrh3yiK67Fo=";
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
    kubeConfig.didactiklabs.enable = true;
    kubeConfig.bealv.enable = true;
    waybar.enable = true;
    nixvimConfig.enable = true;
    gojiConfig.enable = true;
  };
}
