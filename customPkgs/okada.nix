{ pkgs }:
let
  sources = import ../npins;
  klSrc = sources.okada;
  inherit (klSrc) version;
in
pkgs.buildGoModule {
  pname = "okada";
  version = "${version}";

  src = klSrc;

  vendorHash = "sha256-m94dSfozBZMObZ+2C3Nkwcbi905aK+NaX2TphO4DXQk=";
  ldflags = [
    "-s"
    "-w"
    "-X github.com/Banh-Canh/okada/cmd.version=${version}"
  ];

  subPackages = [ "." ];

  meta = {
    mainProgram = "okada";
  };
}
