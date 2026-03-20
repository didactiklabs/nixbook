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
    treefmt.enable = true;
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
          "assets/dms/plugins/**/translations.js"
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
    generate-docs.exec = ''
      nix-build docs/generate-docs.nix "$@" && cp result/MODULES.md docs/MODULES.md && echo "Documentation written to docs/MODULES.md"
    '';
  };

  enterShell = ''
    mkdir -p .tmp/
    hello
    echo ""
    echo "Available custom scripts:"
    echo "  hello     - Prints the greeting message"
    echo "  build-iso - Builds the installation ISO"
    echo "  test-iso       - Builds and tests the installation ISO in a VM"
    echo "  generate-docs  - Auto-generates module documentation to docs/MODULES.md"
  '';

  # https://devenv.sh/tests/
  enterTest = ''
    echo "Running tests"
    hello | grep "Welcome"
  '';
}
