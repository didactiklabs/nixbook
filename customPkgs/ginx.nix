{ pkgs }:
let
  sources = import ../npins;
  ginxSrc = sources.ginx;
in
pkgs.buildGoModule rec {
  pname = "ginx";
  version = "nix";

  src = ginxSrc;

  vendorHash = "sha256-ehNpGLnEGrcqbk1FGVDJEtBroSnvt8oUCxy1oXlV3so=";

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
