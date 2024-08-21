args@{ ... }:
let
  base = import ../../base.nix (args // { inherit hostname; });
  hostname = "nishinoya";
in base
