{ pkgs }:
let
  sources = import ../npins;
  ginxSrc = sources.ginx;
in
pkgs.buildGoModule rec {
  pname = "ginx";
  version = "nix";

  src = ginxSrc;

  vendorHash = "sha256-DYAfFgiSAIqglVcOr1u4vyCsNPktyO/WM20egKiYzno=";

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
