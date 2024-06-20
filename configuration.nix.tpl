args @ { config, pkgs, ... }:
let
   base = import ./base.nix (args // { inherit hostname; });
   hostname = "%HOSTNAME%";
in base
