{ pkgs }:
let
  sources = import ../npins;
  klSrc = sources.kl;
in
pkgs.buildGoModule {
  pname = "kl";
  version = "nix";

  src = klSrc;

  vendorHash = "sha256-oetOkoXpXUFtkGEyWMx0mQiEq6L93Hmv4TFmTC0XDTo=";

  subPackages = [ "." ];

  meta = {
    homepage = "https://github.com/robinovitch61/kl";
    description = "An interactive Kubernetes log viewer for your terminal.";
    mainProgram = "kl";
  };
}
