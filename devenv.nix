{ pkgs, ... }:
{
  # https://devenv.sh/basics/
  env.GREET = "Welcome to the Nixbook NixOS configuration environment!";

  packages = with pkgs; [
    git
    colmena
    npins
    ragenix
  ];

  git-hooks.hooks = {
    # lint shell scripts
    shellcheck.enable = true;
    # execute example shell from Markdown files
    mdsh.enable = true;
    nixfmt-rfc-style.enable = true;
    prettier.enable = true;
  };

  difftastic.enable = true;
  treefmt = {
    enable = true;
    config.programs = {
      nixfmt.enable = true;
      prettier = {
        enable = true;
        excludes = [
          ".git"
          ".devenv"
        ];
        settings = {
          proseWrap = "preserve";
        };
      };
      shfmt.enable = true;
    };
  };
  scripts = {
    # https://devenv.sh/scripts/
    hello.exec = ''
      echo $GREET
    '';
    build-iso.exec = ''
      nix-build default.nix -A buildIso "$@"
    '';
    test-iso.exec = ''
      nix-build default.nix -A testVm "$@" && ./result/bin/test-iso-vm
    '';
  };

  enterShell = ''
    mkdir -p .tmp/
    hello
    echo ""
    echo "Available custom scripts:"
    echo "  hello     - Prints the greeting message"
    echo "  build-iso - Builds the installation ISO"
    echo "  test-iso  - Builds and tests the installation ISO in a VM"
  '';

  # https://devenv.sh/tests/
  enterTest = ''
    echo "Running tests"
    hello | grep "Welcome"
  '';
}
