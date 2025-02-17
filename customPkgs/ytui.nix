{ pkgs }:
let
  sources = import ../npins;
  ytuiSrc = sources.ytui;
in
pkgs.buildGoModule rec {
  pname = "ytui";
  version = "nix";

  src = ytuiSrc;

  vendorHash = "sha256-6JB4pgMNnIeSyAp5S4GwNelth/tf8nJ7yVbkOemIK4Y=";

  subPackages = [ "." ];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/banh-canh/ytui/cmd.version=${version}"
  ];

  meta = {
    homepage = "https://github.com/banh-canh/ytui";
    description = " ytui is a TUI tool that allows users to query videos on youtube and play them in their local player.";
    license = "mit";
    mainProgram = "ytui";
  };
}
