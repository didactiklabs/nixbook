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

  vendorHash = "sha256-wmM3qWzNnb4zis5JhZNd2iXV6gzy1dMagADYh/hzKuc=";

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
