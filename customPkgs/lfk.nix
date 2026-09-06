{ pkgs }:
let
  sources = import ../npins;
  lfkSrc = sources.lfk;
  inherit (lfkSrc) version;
in
pkgs.buildGoModule {
  pname = "lfk";
  version = "${version}";

  src = lfkSrc;

  vendorHash = "sha256-6ggE3voXdV8Yfv9fzdXFTI2zVPMfdPy6D8bWASRMc1g=";

  subPackages = [ "." ];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/janosmiko/lfk/internal/version.Version=${version}"
  ];

  meta = {
    homepage = "https://github.com/janosmiko/lfk";
    description = "Lightning Fast Kubernetes navigator - keyboard-focused, yazi-inspired TUI for managing Kubernetes clusters";
    license = "apache-2.0";
    mainProgram = "lfk";
  };
}
