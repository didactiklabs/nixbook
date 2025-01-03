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
          url = "https://i.imgur.com/2ck3nKs.jpeg";
          sha256 = "sha256-rLcsHaUmW/JcPxofYBI68SlrsLBhJOURjLae6Fr3kdE=";
        };
      in
      "${image}";
    lockWallpaper =
      let
        image = pkgs.fetchurl {
          url = "https://i.imgur.com/2A57JH9.jpeg";
          sha256 = "sha256-SSqK0hAcnl2bsZgVfqnOigDV3/5Xy5QvyRqef1Nbl1s=";
        };
      in
      "${image}";
    startup_audio = pkgs.fetchurl {
      url = "https://github.com/didactiklabs/misc-assets/raw/refs/heads/main/assets/sounds/startup_totoro.mp3";
      sha256 = "sha256-CWl7PBtj6EghkTZ/QafUindrIOr1bD8Riyx6YAqeJns=";
    };
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
    atuinConfig.didactiklabs.enable = true;
    # ghosttyConfig.enable = true;
    kittyConfig.enable = true;
  };
}
