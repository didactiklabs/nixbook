{ pkgs, ... }:
let
  moonfin = import ../../../customPkgs/moonfin.nix { inherit pkgs; };
  pear-desktop = import ../../../customPkgs/pear-desktop.nix { inherit pkgs; };
in
{
  imports = [
    ./gitConfig.nix
    ./niriConfig.nix
    ./fastfetchConfig.nix
  ];

  home.packages = [
    pkgs.moonlight-qt
    pkgs.anki
    moonfin
    pear-desktop
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

    # Input methods cycled with Ctrl+Space: US QWERTY (default) → Vietnamese
    # (Lotus) → Japanese (Mozc) → Schnelle Umlaute (German umlauts via
    # hold-letter + Space gesture).
    fcitx5Config = {
      enable = true;
      addons = with pkgs; [
        fcitx5-mozc-ut
        fcitx5-gtk
      ];
      inputMethods = [
        "keyboard-us"
        "lotus"
        "mozc"
        "schnelle-umlaute"
      ];
      defaultLayout = "us";
      defaultIM = "keyboard-us";
      schnelleUmlaute = true;
      lotus = true;
    };

    # Everyday apps + browser + media
    desktopApps.enable = true;
    zenBrowserConfig = {
      enable = true;
      offerToSaveLogins = true;
    };

    # Git (basic, not a dev box but handy)
    gitConfig.enable = true;
    moonfinConfig.enable = true;

    # Sim racing: Oversteer profile for the Fanatec CSL DD / GT DD Pro
    # (requires customNixOSModules.simracing.enable on the host). Base FFB tune
    # (NDP/NFR/NIN/FEI) is set on the wheelbase OLED menu, not here.
    oversteerConfig.enable = true;
  };
}
