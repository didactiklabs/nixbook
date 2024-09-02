{ pkgs }:
let
  sources = import ../npins;
  goreadSrc = sources.goread;
in
pkgs.buildGoModule {
  pname = "goread";
  version = "nix";

  src = goreadSrc;

  vendorHash = "sha256-/kxEnw8l9S7WNMcPh1x7xqiQ3L61DSn6DCIvJlyrip0=";

  subPackages = [ "." ];

  meta = {
    homepage = "https://github.com/TypicalAM/goread";
    description = "Beautiful program to read your RSS/Atom feeds right in the terminal! ";
    mainProgram = "$pname";
  };
}
