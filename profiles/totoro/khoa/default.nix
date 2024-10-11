{ pkgs, ... }:
{
  imports = [
    ./gitConfig.nix
    ./kanshiConfig.nix
    ./config.nix
    ./hyprlandConfig.nix
  ];
  home.packages = [ pkgs.moonlight-qt ];
  profileCustomization = {
    mainWallpaper =
      let
        image = pkgs.fetchurl {
          url = "https://images4.alphacoders.com/120/thumb-1920-120624.jpg";
          sha256 = "sha256-FfTtWM6+F/eIr2EbpQFO4TR9BctsKI7royWccAGmfEY=";
        };
      in
      "${image}";
    lockWallpaper =
      let
        image = pkgs.fetchurl {
          url = "https://images6.alphacoders.com/602/thumb-1920-602926.jpg";
          sha256 = "sha256-7dcqeWJsQV21BuxqNI0ViqqgnTjrvBFE9OBoTmUyc2U=";
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
