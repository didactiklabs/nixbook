args @ { config, pkgs, ... }:
let
   base = import ./base.nix (args // { inherit username hostname; });
   username = "%USERNAME%";
   hostname = "%HOSTNAME%";
in base
