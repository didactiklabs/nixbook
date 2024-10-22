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
          url = "https://images8.alphacoders.com/738/thumb-1920-738090.png";
          sha256 = "sha256-DGffuB2MCSkpVfgzeUEreRCTMN3oyf92nam1AAa3kJM=";
        };
      in
      "${image}";
    lockWallpaper =
      let
        image = pkgs.fetchurl {
          url = "https://4kwallpapers.com/images/wallpapers/shoyo-hinata-3840x2160-14065.png";
          sha256 = "sha256-gwCrD4ABHfIyFhRMqbz7tHQ+KKJ8qFcJO3kYLIrShdc=";
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
