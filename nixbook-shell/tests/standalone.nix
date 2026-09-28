/*
  nixbook-shell/ is self-contained: copied alone to the store (so any path
  reaching outside it breaks evaluation), it still instantiates its package and
  a Home Manager configuration with only `programs.nixbook-shell` enabled.
  Evaluates to "ok" (nothing is built):

    nix-instantiate --eval --strict tests/standalone.nix \
      --arg homeManager 'builtins.fetchTarball "…/home-manager/archive/<rev>.tar.gz"'
*/
{
  pkgs ? import (import ../npins).nixpkgs { },
  # A Home Manager checkout matching `pkgs`.
  homeManager,
}:
let
  alone = builtins.path {
    path = ../.;
    name = "nixbook-shell";
  };
  shell = import alone { inherit pkgs; };
  home = import "${homeManager}/modules" {
    inherit pkgs;
    configuration = {
      imports = [ shell.homeManagerModules.default ];
      home = {
        username = "test";
        homeDirectory = "/home/test";
        stateVersion = "25.05";
      };
      programs.nixbook-shell = {
        enable = true;
        settings.bar.bottom = true;
      };
    };
  };
in
builtins.seq shell.package.drvPath (builtins.seq home.activationPackage.drvPath "ok")
