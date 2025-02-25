{ pkgs }:
let
  sources = import ../npins;
  souSrc = sources.sou;
in
pkgs.buildGoModule {
  pname = "sou";
  version = "nix";

  src = souSrc;

  vendorHash = "sha256-6kgiZx/g1PA7R50z7noG+ql+S9wSgTuVTkY5DIqeJHY=";

  subPackages = [ "." ];

  meta = {
    homepage = "https://github.com/knqyf263/sou";
    mainProgram = "sou";
  };
}
