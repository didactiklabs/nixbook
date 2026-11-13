{
  pkgs,
  lib,
  config,
  ...
}:
let
  inherit (pkgs.customPkgs) actual-budget moonfin;
  # Bridged (nixbook-shell): it opens music.youtube.com links itself.
  pear-desktop = config.customHomeManagerModules.nixbookShellConfig.electronA11y pkgs.customPkgs.pear-desktop "pear-desktop";
  # Gmail's desktop app (bridged: it opens mail.google.com links itself; the
  # assistant's mail goes through Gmail's API, nixbook-accounts).
  meru = config.customHomeManagerModules.nixbookShellConfig.electronA11y pkgs.customPkgs.meru "meru";
in
{
  imports = [
    ./gitConfig.nix
    ./config.nix
    ./niriConfig.nix
    ./thunderbirdConfig.nix
    ./nixbookShellConfig.nix
  ];
  home.packages = [
    (config.customHomeManagerModules.nixbookShellConfig.electronA11y pkgs.slack "slack")
    pkgs.moonlight-qt
    pkgs.anki
    (config.customHomeManagerModules.nixbookShellConfig.electronA11y actual-budget "actual-budget")
    moonfin
    pear-desktop
    meru
  ];
  # Mail links (mailto:) open a message to write in Meru.
  xdg.mimeApps.defaultApplications."x-scheme-handler/mailto" = "meru.desktop";
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
    ocmConfig.enable = true;
    fontConfig.enable = true;
    gitConfig.enable = true;
    gtkConfig.enable = true;
    sshConfig.enable = true;
    starship.enable = true;
    swayConfig.enable = false;
    niriConfig.enable = true;
    fastfetchConfig.enable = true;
    desktopApps.enable = true;
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
    opencodeConfig.enable = true;
    zenBrowserConfig = {
      enable = true;
      # YouTube Music links (clicked in Zen or opened by other apps) open in
      # the app (but songs and playlists: nixbookShellConfig.youtubeLinks),
      # Gmail's open in Meru.
      openInApps = (pear-desktop.nixbookOpenLinks or { }) // (meru.nixbookOpenLinks or { });
    };
    rtk = {
      enable = true;
    };
    # Desktop shell. dmsConfig (DankMaterialShell) and nixbookShellConfig (nixbook-shell) are
    # mutually exclusive — flip these two to switch back.
    dmsConfig = {
      enable = false;
      showDock = true;
    };
    nixbookShellConfig = {
      enable = true;
      # The desktop agent fixing nixbook by PR: this machine only, for now.
      selfImprove.enable = true;
      # YouTube videos play in mpv, YouTube Music songs and playlists in the
      # shell's background player (the right panel's tabs), from Zen and
      # every other app; the rest of music.youtube.com still opens the app.
      youtubeLinks.enable = true;
    };
    rbwConfig = {
      enable = true;
      email = "vhvictorhang@gmail.com";
      baseUrl = "https://pass.bealv.io";
    };
  };
}
