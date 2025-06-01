{ pkgs }:
let
  sources = import ../npins;
  klSrc = sources.kl;
in
pkgs.buildGoModule {
  pname = "kl";
  version = "nix";

  src = klSrc;

  vendorHash = "sha256-baXXNnK1UfFef/pFaSvhzmj4VzoaM0TmL8I79VFfdb8=";

  subPackages = [ "." ];

  meta = {
    homepage = "https://github.com/robinovitch61/kl";
    description = "An interactive Kubernetes log viewer for your terminal.";
    mainProgram = "kl";
  };
}
