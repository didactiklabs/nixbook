{
  pkgs,
  lib,
  ...
}:
let
  sources = import ../../../npins;
  pkgs-unstable = import sources.nixpkgs-unstable { };
  sdl = pkgs.SDL2.overrideAttrs (oldAttrs: {
    version = "2.32.54";
    src = pkgs.fetchFromGitHub {
      owner = "libsdl-org";
      repo = "sdl2-compat";
      rev = "main";
      hash = "sha256-u4iGtmtvQFA+6Z3GFnd+WA4YiQRXYceHzQ76PA16VnQ=";
    };
  });
in
{
  imports = [
    ./gitConfig.nix
    ./kanshiConfig.nix
    ./config.nix
    ./hyprlandConfig.nix
  ];
  home.packages = [
    sdl
    pkgs-unstable.sdl3
    pkgs.moonlight-qt
    pkgs.jellyfin-media-player
  ];
  programs.go = {
    enable = true;
    goPath = lib.mkForce ".local/go";
  };

  profileCustomization = {
    mainWallpaper =
      let
        image = pkgs.fetchurl {
          url = "https://i.imgur.com/sEZYXQp.jpeg";
          sha256 = "sha256-uSQokHcEOCta68SBavE2QVItD4vLrC5i/BM9iriYnfU=";
        };
      in
      "${image}";
    lockWallpaper =
      let
        image = pkgs.fetchurl {
          url = "https://i.imgur.com/KQgHVef.jpeg";
          sha256 = "sha256-7ybKMprmJBNamRkIJNKLGdAPThI8h3jvBHjt9M0+PbY=";
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
