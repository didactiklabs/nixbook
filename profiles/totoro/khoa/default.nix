{
  pkgs,
  lib,
  config,
  ...
}:
let
  actual-budget = import ../../../customPkgs/actual-budget.nix { inherit pkgs; };
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
    pkgs.slack
    pkgs.moonlight-qt
    pkgs.anki
    actual-budget
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
    ocmConfig.enable = true;
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
    # Desktop shell. dmsConfig (DankMaterialShell) and nixbookShellConfig (nixbook-shell) are
    # mutually exclusive — flip these two to switch back.
    dmsConfig = {
      enable = false;
      showDock = true;
    };
    nixbookShellConfig = {
      enable = true;
      settings = {
        appearance.persona.enable = true;
        # Personal Persona cut-in rules: these lists override the shared ones
        # (homeManagerModules/nixbookShellConfig/settings.nix, set as defaults).
        notifications.cutIn = {
          keywords = [
            # Calendar events
            "Calendar"
            "Reminder"
            "Google Agenda"
            # Family and friends
            "Alesio"
            "chocomooncake"
            "choco mooncake"
            "wolfey182"
            "huyền"
            "Huyen"
            "\"Diệu\""
            "Trang HANG"
            "Tin Dinh"
            "aamoyel"
            "Alan Amoyel"
            # About me: mentions and answers to my messages — only in the
            # message text (a title or sender holding my name is my own
            # conversation or message), and not in mail (newsletters say
            # "Hi Victor" too).
            "body:\"@vtk_hg\""
            "body:\"@victortk\""
            "body:Victor Tiến Khoa + !app:Thunderbird"
            "body:Victor Hang + !app:Thunderbird"
            "body:ビクタ + !app:Thunderbird"
            "body:mentioned you"
            "body:tagged you"
            "body:replied to you"
            "body:to your message"
          ];
          # My own messages: sent lines start with my name or handle.
          blacklist = [
            "body:^\"You:\""
            "body:^\"Vous:\""
            "body:^\"Bạn:\""
            "body:^\"Victor Hang:\""
            "body:^\"Victor Tiến Khoa Hang:\""
            "body:^\"Victor Tiến Khoa:\""
            "body:^\"vtk_hg:\""
            "body:^\"victortk:\""
          ];
        };
      };
    };
    rbwConfig = {
      enable = true;
      email = "vhvictorhang@gmail.com";
      baseUrl = "https://pass.bealv.io";
    };
  };
}
