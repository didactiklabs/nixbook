{ pkgs }:
let
  sources = import ../npins;
  sofkaSrc = sources.sofka;
in
pkgs.rustPlatform.buildRustPackage {
  pname = "sofka";
  version = "unstable-${sofkaSrc.revision}";

  src = sofkaSrc;

  cargoLock.lockFile = "${sofkaSrc}/Cargo.lock";

  doCheck = false;

  meta = {
    homepage = "https://github.com/nklmilojevic/sofka";
    description = "A Kubernetes TUI, reimagined in Rust";
    license = with pkgs.lib.licenses; [
      mit
      asl20
    ];
    mainProgram = "sofka";
  };
}
