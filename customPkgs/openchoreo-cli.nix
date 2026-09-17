{ pkgs }:
let
  sources = import ../npins;
  openchoreoSrc = sources.openchoreo;
  inherit (openchoreoSrc) version revision;
  versionPackage = "github.com/openchoreo/openchoreo/internal/version";
in
pkgs.buildGoModule {
  pname = "openchoreo-cli";
  version = "${version}";

  src = openchoreoSrc;

  vendorHash = "sha256-5MvPrLUqNdxbcHJUZlhsExqYOZix5UN6/Et21KmOkxs=";

  subPackages = [ "cmd/occ" ];

  ldflags = [
    "-s"
    "-w"
    "-X ${versionPackage}.version=${version}"
    "-X ${versionPackage}.gitRevision=${revision}"
    "-X ${versionPackage}.componentName=occ"
  ];

  # The repo ships extensive test suites that require a live cluster.
  doCheck = false;

  meta = {
    homepage = "https://github.com/openchoreo/openchoreo";
    description = "OpenChoreo CLI (occ) — command-line interface for the OpenChoreo internal developer platform.";
    mainProgram = "occ";
  };
}
