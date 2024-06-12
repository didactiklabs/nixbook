{
  config,
  pkgs,
  lib,
  username,
  ...
}: {
  customNixOSModules = {
    laptopProfile.enable = true;
    networkManager.enable = true;
  };
  networking.hostName = lib.mkForce "nixsus";
  home-manager = {
    users."${username}" = {
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
        sway.enable = true;
        sshConfig.enable = true;
        starship.enable = true;
        vim.enable = true;
        vscode.enable = true;
        pywalConfig.enable = false;
        stylixConfig.enable = true;
        # https://github.com/adi1090x/rofi
        rofiConfig = {
          enable = true;
          launcher = {
            type = "type-3";
            style = "style-4";
          };
          color = "cyberpunk";
        };
      };
      imports = [
        ./kanshiConfig.nix
        ./gitConfig.nix
        ./swayConfig.nix
      ];
    };
  };
}
