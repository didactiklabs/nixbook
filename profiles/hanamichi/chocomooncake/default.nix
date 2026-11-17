{ pkgs, config, ... }:
let
  inherit (pkgs.customPkgs) moonfin;
  # YouTube Music, readable by the desktop agents (lib/electronA11y.nix).
  pear-desktop = config.customHomeManagerModules.nixbookShellConfig.electronA11y pkgs.customPkgs.pear-desktop "pear-desktop";
  # Octave with the compilers its own installer needs (nixpkgs' withPackages
  # makes the package list read-only, so the two do not mix):
  # `pkg install -forge NAME` builds a package into ~/.local/share/octave.
  # Those are compiled for one Octave version: to install again after an update.
  octave = pkgs.symlinkJoin {
    name = "octave-with-pkg-install";
    paths = [ pkgs.octaveFull ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      for bin in "$out"/bin/*; do
        wrapProgram "$bin" --prefix PATH : ${
          pkgs.lib.makeBinPath [
            pkgs.gcc
            pkgs.gfortran
            pkgs.gnumake
            pkgs.pkg-config
            pkgs.autoconf
            pkgs.automake
          ]
        }
      done
      # The launcher entry names the unwrapped Octave by its store path.
      for entry in "$out"/share/applications/*.desktop; do
        cp --remove-destination "$(realpath "$entry")" "$entry"
        sed -i "s|^Exec=[^ ]*/bin/octave|Exec=$out/bin/octave|" "$entry"
      done
    '';
  };
in
{
  imports = [
    ./gitConfig.nix
    ./niriConfig.nix
    ./fastfetchConfig.nix
    ./cursorConfig.nix
    ./nixbookShellConfig.nix
  ];

  home.packages = [
    pkgs.moonlight-qt
    pkgs.anki
    octave
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
    # Desktop shell: nixbook-shell (was DankMaterialShell, dmsConfig; the
    # two are mutually exclusive). The shared settings show the dock.
    nixbookShellConfig.enable = true;

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
      # YouTube Music links (clicked in Zen or opened by other apps) play in
      # the app: listening along shares and follows the app's player, not
      # a browser tab.
      openInApps = pear-desktop.nixbookOpenLinks or { };
    };

    # Git (basic, not a dev box but handy)
    gitConfig.enable = true;

    # Sim racing: Oversteer profile for the Fanatec CSL DD / GT DD Pro
    # (requires customNixOSModules.simracing.enable on the host). Base FFB tune
    # (NDP/NFR/NIN/FEI) is set on the wheelbase OLED menu, not here.
    oversteerConfig.enable = true;
  };
}
