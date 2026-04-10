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

  # Fix upstream hash mismatch: the GitHub-generated patch for PR #23326
  # changed content, breaking the pinned hash in nixpkgs.
  openapi-generator-cli = prev.openapi-generator-cli.overrideAttrs (oldAttrs: {
    patches = [
      (prev.fetchpatch {
        url = "https://github.com/OpenAPITools/openapi-generator/pull/23326.patch";
        hash = "sha256-E1VgtaIW1V+8ch2RpW850fVNl5Iqitjog+0b8DKFgZw=";
      })
    ];
  });
}
