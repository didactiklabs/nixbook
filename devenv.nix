{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
{
  # https://devenv.sh/basics/
  env.GREET = "Welcome to the NixOS configuration environment!";

  # https://devenv.sh/packages/
  packages = with pkgs; [
    git
    colmena
    npins
    ragenix
  ];

  difftastic.enable = true;
  treefmt = {
    enable = true;
    config.programs = {
      nixfmt.enable = true;
    };
  };

  # https://devenv.sh/languages/
  # languages.nix.enable = true;

  # https://devenv.sh/scripts/
  scripts.hello.exec = ''
    echo $GREET
  '';

  enterShell = ''
    hello
  '';

  # https://devenv.sh/tests/
  enterTest = ''
    echo "Running tests"
    hello | grep "Welcome"
  '';
}
