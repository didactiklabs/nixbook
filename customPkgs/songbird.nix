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

  vendorHash = "sha256-5CDfg/qnhCmR32tft4NFBsH2BM8Ca9m1wymoHL4BQl8=";
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
