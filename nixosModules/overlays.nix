{ sources }:
final: prev:
let
  lixStable = prev.lixPackageSets.stable;
in
{
  inherit (lixStable)
    nixpkgs-review
    nix-eval-jobs
    nix-fast-build
    ;
}
