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
  networking.hostName = lib.mkForce "dusty";
  home-manager = {
    users."${username}" = {
      profileCustomization = {
        mainWallpaper = let
          image = pkgs.fetchurl {
            url = "https://w.wallhaven.cc/full/x6/wallhaven-x6yxel.jpg";
            sha256 = "sha256-KC/MgfiJc8iviyamAvCR69BrZpTzR7SPTINjkmUl+jo=";
          };
        in "${image}";
        lockWallpaper = let
          image = pkgs.fetchurl {
            url = "https://w.wallhaven.cc/full/43/wallhaven-43z9q9.png";
            sha256 = "sha256-Llh2PBTPWtE/OskJZJiLQd5zkYz+OzVgOBLa1zbxrPk=";
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
