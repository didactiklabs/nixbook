{ pkgs }:
let
  sources = import ../npins;
  ginxSrc = sources.ginx;
in
pkgs.buildGoModule rec {
  pname = "ginx";
  # From the pin (its release, else its commit), not a constant: the vendored
  # modules are a fixed-output derivation named after the version, so a
  # constant one would silently reuse a stale vendor dir when the pin moves.
  version = ginxSrc.version or "unstable-${builtins.substring 0 7 ginxSrc.revision}";

  src = ginxSrc;

  proxyVendor = true;
  vendorHash = "sha256-XU8KeBgshHHutp5wdyhKSZWjgUgp+m7gg4R96BjrL0o=";

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
