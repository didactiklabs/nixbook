args @ {...}: let
  base = import ../../base.nix (args // {inherit hostname;});
  hostname = "anya";
in
  base
