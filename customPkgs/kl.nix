{ pkgs }:
let
  sources = import ../npins;
  klSrc = sources.kl;
in
pkgs.buildGoModule {
  pname = "kl";
  # From the pin (its release, else its commit), not a constant: the vendored
  # modules are a fixed-output derivation named after the version, so a
  # constant one would silently reuse a stale vendor dir when the pin moves.
  version = klSrc.version or "unstable-${builtins.substring 0 7 klSrc.revision}";

  src = klSrc;

  vendorHash = "sha256-baXXNnK1UfFef/pFaSvhzmj4VzoaM0TmL8I79VFfdb8=";

  subPackages = [ "." ];

  meta = {
    homepage = "https://github.com/robinovitch61/kl";
    description = "An interactive Kubernetes log viewer for your terminal.";
    mainProgram = "kl";
  };
}
