{
  pkgs,
  lib,
  config,
  ...
}:
let
  actual-budget = import ../../../customPkgs/actual-budget.nix { inherit pkgs; };
  jellyfin-desktop = import ../../../customPkgs/jellyfin-desktop.nix { inherit pkgs; };
  pear-desktop = import ../../../customPkgs/pear-desktop.nix { inherit pkgs; };
in
{
  imports = [
    ./gitConfig.nix
    ./config.nix
    ./niriConfig.nix
    ./thunderbirdConfig.nix
  ];
  home.packages = [
    pkgs.moonlight-qt
    actual-budget
    jellyfin-desktop
    pear-desktop
  ];
  programs = {
    go = {
      enable = true;
      env.GOPATH = lib.mkForce "${config.home.homeDirectory}/.local/go";
    };
    opencode.settings.mcp = {
      trek = {
        type = "remote";
        url = "https://trek.bealv.io/mcp";
      };
    };
  };

  profileCustomization = {
  };
  customHomeManagerModules = {
    cliTools.enable = true;
    devTools.enable = true;
    fontConfig.enable = true;
    gitConfig.enable = true;
    gtkConfig.enable = true;
    sshConfig.enable = true;
    starship.enable = true;
    swayConfig.enable = false;
    hyprlandConfig.enable = false;
    niriConfig.enable = true;
    fastfetchConfig.enable = true;
    desktopApps.enable = true;
    kubeTools.enable = true;
    kubeConfig.didactiklabs.enable = true;
    kubeConfig.bealv.enable = true;
    nixvimConfig.enable = true;
    gojiConfig.enable = true;
    atuinConfig.didactiklabs.enable = true;
    kittyConfig.enable = true;
    zshConfig.enable = true;
    kubeswitchConfig.enable = true;
    # Input methods cycled with Ctrl+Space: French/AZERTY (base, matches the
    # physical key caps) → Vietnamese (Lotus) → Japanese (Mozc) → Schnelle
    # Umlaute (German umlauts via hold-letter + Space gesture).
    fcitx5Config = {
      enable = true;
      addons = with pkgs; [
        fcitx5-mozc-ut
        fcitx5-gtk
      ];
      inputMethods = [
        "keyboard-fr"
        "lotus"
        "mozc"
        "schnelle-umlaute"
      ];
      defaultLayout = "fr";
      defaultIM = "keyboard-fr";
      schnelleUmlaute = true;
      lotus = true;
    };
    thunderbirdConfig.enable = false;
    opencodeConfig = {
      enable = true;
      ollama = {
        enable = true;
        baseUrl = "http://anya:11434/v1";
      };
    };
    zenBrowserConfig.enable = true;
    rtk = {
      enable = true;
    };
    dmsConfig = {
      enable = true;
      showDock = true;
    };
    rbwConfig = {
      enable = true;
      email = "vhvictorhang@gmail.com";
      baseUrl = "https://pass.bealv.io";
    };
  };
  services.kdeconnect.enable = true;
}
