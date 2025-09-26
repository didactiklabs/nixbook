{ pkgs }:
let
  sources = import ../npins;
  leadrSrc = sources.leadr;
in
pkgs.rustPlatform.buildRustPackage {
  pname = "leadr";
  version = "feat-fish-${builtins.substring 0 7 leadrSrc.revision}";

  src = leadrSrc;


  cargoHash = "sha256-trtPj4b0Wd6U4KMNyMgMMO1pmygpDp4oWa/Ab5pra/4=";

  meta = {
    homepage = "https://github.com/Banh-Canh/leadr";
    description = "Shell aliases on steroids";
    license = pkgs.lib.licenses.mit;
    mainProgram = "leadr";
  };
}
