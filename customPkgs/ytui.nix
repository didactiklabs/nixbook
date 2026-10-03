{ pkgs }:
let
  sources = import ../npins;
  ytuiSrc = sources.ytui;
in
pkgs.buildGoModule rec {
  pname = "ytui";
  # From the pin (its release, else its commit), not a constant: the vendored
  # modules are a fixed-output derivation named after the version, so a
  # constant one would silently reuse a stale vendor dir when the pin moves.
  version = ytuiSrc.version or "unstable-${builtins.substring 0 7 ytuiSrc.revision}";

  src = ytuiSrc;

  vendorHash = "sha256-db1g06xpAHSZuz4scVyumika2n0be+iKfR/tdn1gXHQ=";

  subPackages = [ "." ];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/banh-canh/ytui/cmd.version=${version}"
  ];

  meta = {
    homepage = "https://github.com/banh-canh/ytui";
    description = " ytui is a TUI tool that allows users to query videos on youtube and play them in their local player.";
    license = "mit";
    mainProgram = "ytui";
  };
}
