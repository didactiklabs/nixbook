args @ { config, pkgs, ... }:
let
   base = import ./base.nix (args // { inherit username; });
   username = "%USERNAME%";
in base
