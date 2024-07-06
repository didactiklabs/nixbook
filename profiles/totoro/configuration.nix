args @ {...}: let
  base = import ../../base.nix (args // {inherit hostname;});
  hostname = "totoro";
in
  base
