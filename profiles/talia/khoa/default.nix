# khoa on talia: the shell, editor, Kubernetes and AI tools of the NixOS
# machines, totoro's apps where they exist for macOS, and OmniWM (niri-like
# scrolling tiling) instead of niri. Linux desktop modules (niri,
# nixbook-shell, DMS, GTK, fcitx5, desktopApps' Dolphin/imv/OBS…) are left
# off: they don't exist on macOS.
{ pkgs, ... }:
{
  imports = [
    ./gitConfig.nix
  ];

  # Copied into ~/Applications/Home Manager Apps (lib/darwinUserConfig.nix):
  # Spotlight and Launchpad find them. Not on macOS: Nextcloud's client,
  # KDE Connect, OBS, Actual Budget, Meru, Moonfin (Linux builds or AppImages).
  home.packages = with pkgs; [
    vesktop # Discord
    slack
    spotify
    pear-desktop # YouTube Music
    moonlight-qt
    anki-bin
    libreoffice-bin
    mpv
  ];

  customHomeManagerModules = {
    cliTools.enable = true;
    devTools.enable = true;
    fontConfig.enable = true;
    gitConfig.enable = true;
    sshConfig.enable = true;
    starship.enable = true;
    fastfetchConfig.enable = true;
    kubeTools.enable = true;
    kubeConfig = {
      didactiklabs.enable = true;
      bealv.enable = true;
      rpcu.enable = true;
    };
    nixvimConfig.enable = true;
    gojiConfig.enable = true;
    atuinConfig.didactiklabs.enable = true;
    kittyConfig.enable = true;
    zshConfig.enable = true;
    kubeswitchConfig.enable = true;
    opencodeConfig.enable = true;
    rtk.enable = true;
    omniwmConfig.enable = true;
    zenBrowserConfig.enable = true;
    rbwConfig = {
      enable = true;
      email = "vhvictorhang@gmail.com";
      baseUrl = "https://pass.bealv.io";
    };
  };
}
