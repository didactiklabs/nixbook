{ pkgs }:
let
  sources = import ../npins;
  pvmigrateSrc = sources.pvmigrate;
in
pkgs.buildGoModule {
  pname = "pvmigrate";
  version = "nix";

  src = pvmigrateSrc;

  vendorHash = "sha256-BdP/58lUHOS0i/UUowZXAtXVwz7vGDZ/NfhRi9q8iEo=";

  subPackages = [ "cmd" ];
  postInstall = ''
    mv $out/bin/cmd $out/bin/pvmigrate
  '';

  meta = {
    homepage = "https://github.com/robinovitch61/kl";
    description = "An interactive Kubernetes log viewer for your terminal.";
    mainProgram = "kl";
  };
}
