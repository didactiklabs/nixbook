{ pkgs, ... }:
{
  imports = [
    ./gitConfig.nix
    ./sshConfig.nix
    ./kanshiConfig.nix
    ./hyprlandConfig.nix
  ];
  home.packages = [
    # pkgs.jellyfin-mpv-shim
    # pkgs.nextcloud-client
    pkgs.moonlight-qt
    pkgs.google-chrome
    pkgs.mattermost-desktop
    pkgs.bitwarden-desktop
  ];
  profileCustomization = {
    mainWallpaper =
      let
        image = pkgs.fetchurl {
          url = "https://wallpapers-clan.com/wp-content/uploads/2024/04/haikyuu-yuu-nishinoya-blue-sky-desktop-wallpaper-preview.jpg";
          sha256 = "sha256-AQxLXpcMLZK1rmPujYLde9XNdQ/PfyFv8WdBNJdXSe4=";
        };
      in
      "${image}";
    lockWallpaper =
      let
        image = pkgs.fetchurl {
          url = "https://w.wallhaven.cc/full/43/wallhaven-43z9q9.png";
          sha256 = "sha256-Llh2PBTPWtE/OskJZJiLQd5zkYz+OzVgOBLa1zbxrPk=";
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
    spicetifyConfig.enable = true;
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
    kubeConfig = {
      didactiklabs.enable = true;
      logicmg.enable = true;
    };
    waybar.enable = true;
    nixvimConfig.enable = true;
    gojiConfig.enable = true;
    atuinConfig.didactiklabs.enable = true;
    kittyConfig.enable = true;
  };
}
