{ pkgs }:
let
  sources = import ../npins;
  gojiSrc = sources.goji;
in
pkgs.buildGoModule rec {
  pname = "goji";
  version = "0.1.2";

  src = gojiSrc;

  vendorHash = "sha256-81yWKq3hn5tz5j+FmbrrlZe/y2IhLo2XdoVSGnEMOPg=";

  subPackages = [ "." ];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/muandane/goji/cmd.version=${version}"
  ];

  meta = {
    homepage = "https://github.com/muandane/goji";
    description = " Commitizen-like Emoji Commit Tool written in Go (think cz-emoji and other commitizen adapters but in go) 🚀 ";
    changelog = "https://github.com/muandane/goji/blob/v${version}/CHANGELOG.md";
    license = "Apache 2.0 license Zine El Abidine Moualhi";
    mainProgram = "goji";
  };
}
