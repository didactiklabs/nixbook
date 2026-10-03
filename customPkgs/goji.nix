{ pkgs }:
let
  sources = import ../npins;
  gojiSrc = sources.goji;
in
pkgs.buildGoModule rec {
  pname = "goji";
  # From the pin (a branch pin: the last release plus its commit), not a constant: the vendored
  # modules are a fixed-output derivation named after the version, so a
  # constant one would silently reuse a stale vendor dir when the pin moves.
  version = "0.2.1-unstable-${builtins.substring 0 7 gojiSrc.revision}";
  src = gojiSrc;

  vendorHash = "sha256-kkI+8JEpcdHk21kLC3qcaeaH8StZy86AHjdHgYMV++w=";

  subPackages = [ "." ];

  nativeBuildInputs = [ pkgs.installShellFiles ];
  postInstall = ''
    installShellCompletion --cmd goji \
      --zsh <($out/bin/goji completion zsh)
  '';

  ldflags = [
    "-s"
    "-w"
    "-X github.com/muandane/goji/cmd.version=${version}"
  ];

  meta = {
    homepage = "https://github.com/muandane/goji";
    description = " Commitizen-like Emoji Commit Tool written in Go (think cz-emoji and other commitizen adapters but in go) 🚀 ";
    changelog = "https://github.com/muandane/goji/blob/${gojiSrc.revision}/CHANGELOG.md";
    license = "Apache 2.0 license Zine El Abidine Moualhi";
    mainProgram = "goji";
  };
}
