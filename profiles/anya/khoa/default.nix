{pkgs, ...}: {
  imports = [
    ./gitConfig.nix
    ./swayConfig.nix
    ./sunshine.nix
  ];
  profileCustomization = {
    mainWallpaper = let
      image = pkgs.fetchurl {
        url = "https://w.wallhaven.cc/full/5g/wallhaven-5gp535.png";
        sha256 = "sha256-Ip4Kox49zJxYIGxtisI0qcWcc/MSzeeEdsxJIiHUcvg=";
      };
    in "${image}";
    lockWallpaper = let
      image = pkgs.fetchurl {
        url = "https://w.wallhaven.cc/full/5g/wallhaven-5gp535.png";
        sha256 = "sha256-Ip4Kox49zJxYIGxtisI0qcWcc/MSzeeEdsxJIiHUcvg=";
      };
    in "${image}";
  };
  customHomeManagerModules = {
    bluetooth.enable = false;
    fontConfig.enable = true;
    gitConfig.enable = true;
    gtkConfig.enable = true;
    sshConfig.enable = true;
    starship.enable = true;
    swayConfig.enable = true;
    nixvimConfig.enable = true;
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
    copyqConfig.enable = false;
    fastfetchConfig.enable = true;
    desktopApps.enable = false;
    kubeTools.enable = false;
    waybar.enable = true;
  };
}
