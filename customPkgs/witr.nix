{ pkgs }:
let
  sources = import ../npins;
  klSrc = sources.witr;
  inherit (klSrc) version;
in
pkgs.buildGoModule {
  pname = "witr";
  version = "${version}";

  src = klSrc;

  vendorHash = null;
  ldflags = [
    "-s"
    "-w"
    "-X main.version=${version}"
  ];

  subPackages = [ "cmd/witr" ];

  meta = {
    mainProgram = "witr";
  };
}
