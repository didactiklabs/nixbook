{ pkgs, ... }: {
  imports = [
    ./gitConfig.nix
    ./niriConfig.nix
    ./fastfetchConfig.nix
  ];

  home.packages = [
    pkgs.moonlight-qt
    pkgs.ytmdesktop
    pkgs.anki
  ];

  customHomeManagerModules = {
    # Desktop / appearance
    fontConfig.enable = true;
    gtkConfig.enable = true;
    starship.enable = true;
    fastfetchConfig.enable = true;
    niriConfig.enable = true;
    nixvimConfig.enable = true;
    vscode.enable = true;
    dmsConfig = {
      enable = true;
      showDock = true;
    };

    # Terminal / shell
    kittyConfig.enable = true;
    zshConfig.enable = true;
    atuinConfig.didactiklabs.enable = true;

    # Everyday apps + browser + media
    desktopApps.enable = true;
    zenBrowserConfig.enable = true;

    # Git (basic, not a dev box but handy)
    gitConfig.enable = true;
  };
}
