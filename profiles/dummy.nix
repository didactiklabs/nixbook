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
  networking.hostName = lib.mkForce "dummy-profile";
  home-manager = {
    users."${username}" = {
      customHomeManagerModules = {
        bluetooth.enable = true;
        fontConfig.enable = true;
        gitConfig.enable = true;
        gtkConfig.enable = true;
        sway.enable = true;
        hyprland.enable = false;
        sshConfig.enable = true;
        starship.enable = true;
        vim.enable = true;
        stylixConfig.enable = false;
        # https://github.com/adi1090x/rofi
        rofiConfig = {
          enable = true;
          launcher = {
            type = "type-1";
            style = "style-1";
          };
          powermenu = {
            style = "style-1"; #(1 - 5) # type-1 only
          };
          color = "onedark";
          copyqConfig.enable = true;
          fastfetchConfig.enable = true;
          desktopApps.enable = true;
        };
      };
    };
  };
}
