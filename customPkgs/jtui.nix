{ pkgs }:
let
  sources = import ../npins;
  jtuiSrc = sources.jtui;
in
pkgs.buildGoModule rec {
  pname = "jtui";
  # From the pin (its release, else its commit), not a constant: the vendored
  # modules are a fixed-output derivation named after the version, so a
  # constant one would silently reuse a stale vendor dir when the pin moves.
  version = jtuiSrc.version or "unstable-${builtins.substring 0 7 jtuiSrc.revision}";

  src = jtuiSrc;

  vendorHash = "sha256-pRTi+xnbDYPZl1EYaaxwe+TymX+Osir5Tg12z128NDs=";

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
