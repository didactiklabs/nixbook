{ pkgs }:
let
  sources = import ../npins;
  ytuiSrc = sources.ytui;
in
pkgs.buildGoModule rec {
  pname = "ytui";
  version = "nix";

  src = ytuiSrc;

  vendorHash = "sha256-STo94gb4GymNxtk+/O3cC0cKVd8T0JvCtCM9za4V+n4=";

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
