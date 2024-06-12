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
            url = "https://w.wallhaven.cc/full/gp/wallhaven-gpl8d3.jpg";
            sha256 = "sha256-t5f3VOHHZcaiGasyTyFh8eL87c0mq2FCsPVNNj20gqg=";
          };
        in "${image}";
        lockWallpaper = let
          image = pkgs.fetchurl {
            url = "https://w.wallhaven.cc/full/yx/wallhaven-yx35z7.jpg";
            sha256 = "sha256-bHNsg9ftOSJRxChC5jnvb1U+4oGwr118gCFcCn8/YQU=";
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
        rofiConfig.enable = true;
      };
      imports = [
        ./kanshiConfig.nix
        ./gitConfig.nix
        ./swayConfig.nix
      ];
    };
  };
}
