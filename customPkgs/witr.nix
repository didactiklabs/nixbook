{ pkgs }:
let
  sources = import ../npins;
  witrSrc = sources.witr;
  inherit (witrSrc) version;
in
pkgs.buildGoModule {
  pname = "witr";
  version = "${version}";

  src = witrSrc;

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
