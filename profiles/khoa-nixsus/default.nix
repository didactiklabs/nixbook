{
  config,
  pkgs,
  lib,
  username,
  hostname,
  ...
}: {
  customNixOSModules = {
    laptopProfile.enable = true;
    networkManager.enable = true;
  };
  home-manager = {
    users."${username}" = {
      home.packages = [
        pkgs.jellyfin-mpv-shim
        pkgs.nextcloud-client
        pkgs.moonlight-qt
      ];
      profileCustomization = {
        mainWallpaper = let
          image = pkgs.fetchurl {
            url = "https://w.wallhaven.cc/full/ex/wallhaven-exzrmw.png";
            sha256 = "sha256-E8xvHLciXUKjXCzR9AlUWpT7B5+3c5qYkgpdbU0e03E=";
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
        sway.enable = true;
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
          color = "cyberpunk";
        };
        copyqConfig.enable = true;
        fastfetchConfig.enable = true;
        desktopApps.enable = true;
        kubeTools.enable = true;
      };
      imports = [
        ./kanshiConfig.nix
        ./gitConfig.nix
        ./swayConfig.nix
      ];
    };
  };
}
