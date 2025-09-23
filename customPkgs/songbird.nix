{ pkgs }:
let
  sources = import ../npins;
  klSrc = sources.songbird;
  inherit (klSrc) version;
in
pkgs.buildGoModule {
  pname = "songbird";
  version = "${version}";

  src = klSrc;

  vendorHash = "sha256-mcbLV7HzDK0APJ+IPEBpHk3CH1Vm4a2Wjts/aElq3dw=";
  ldflags = [
    "-s"
    "-w"
    "-X github.com/Banh-Canh/songbird/cmd.version=${version}"
  ];

  subPackages = [ "." ];

  meta = {
    mainProgram = "songbird";
  };
}
