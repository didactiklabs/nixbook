{ pkgs }:
let
  sources = import ../npins;
  ginxSrc = sources.ginx;
in
pkgs.buildGoModule rec {
  pname = "ginx";
  version = "nix";

  src = ginxSrc;

  proxyVendor = true;
  vendorHash = "sha256-Oljt4474096IgAUOepW5hSBwa1Ts1OJkQCNb9BdOhh4=";

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
