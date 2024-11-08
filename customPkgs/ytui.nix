{ pkgs }:
let
  sources = import ../npins;
  ytuiSrc = sources.ytui;
in
pkgs.buildGoModule rec {
  pname = "ytui";
  version = "nix";

  src = ytuiSrc;

  vendorHash = "sha256-cjw31yOHZ8y//iCd3acr4VHW0H9rdbO8UgHVZQYd/Hk=";

  subPackages = [ "." ];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/muandane/goji/cmd.version=${version}"
  ];

  meta = {
    homepage = "https://github.com/banh-canh/ytui";
    description = " ytui is a TUI tool that allows users to query videos on youtube and play them in their local player.";
    license = "mit";
    mainProgram = "ytui";
  };
}
