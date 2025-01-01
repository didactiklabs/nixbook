{ pkgs }:
let
  sources = import ../npins;
  ginxSrc = sources.ginx;
in
pkgs.buildGoModule rec {
  pname = "ginx";
  version = "nix";

  src = ginxSrc;

  vendorHash = "sha256-Ktqa+6EmniwsplX3jsgklhsvuhQocQhFfW4jug0ra+Y=";

  subPackages = [ "." ];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/didactiklabs/ginx/cmd.version=${version}"
  ];

  meta = {
    homepage = "https://github.com/didactiklabs/ginx";
    mainProgram = "ginx";
  };
}
