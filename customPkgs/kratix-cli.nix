{ pkgs }:
let
  sources = import ../npins;
  kratixCliSrc = sources.kratix-cli;
  inherit (kratixCliSrc) version;
in
pkgs.buildGoModule {
  pname = "kratix-cli";
  version = "${version}";

  src = kratixCliSrc;

  vendorHash = "sha256-O/86Ig+rEGCFkeo6KsUvpltZMsuka/aDc0D+7cWB06I=";

  subPackages = [ "cmd/kratix" ];

  ldflags = [
    "-s"
    "-w"
  ];

  meta = {
    homepage = "https://github.com/syntasso/kratix-cli";
    description = "CLI-based tool to build Kratix Promises.";
    mainProgram = "kratix";
  };
}
