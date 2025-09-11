{ pkgs }:
let
  sources = import ../npins;
  jtuiSrc = sources.jtui;
in
pkgs.buildGoModule rec {
  pname = "jtui";
  version = "nix";

  src = jtuiSrc;

  vendorHash = "sha256-bAA8P8PnSXKro51tppx2rCiAJd09q/bgIp4VgW+M6DU=";

  subPackages = [ "." ];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/banh-canh/jtui/cmd.version=${version}"
  ];

  meta = {
    homepage = "https://github.com/banh-canh/jtui";
    license = "mit";
    mainProgram = "jtui";
  };
}
