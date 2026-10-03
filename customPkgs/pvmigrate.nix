{ pkgs }:
let
  sources = import ../npins;
  pvmigrateSrc = sources.pvmigrate;
in
pkgs.buildGoModule {
  pname = "pvmigrate";
  # From the pin (its release, else its commit), not a constant: the vendored
  # modules are a fixed-output derivation named after the version, so a
  # constant one would silently reuse a stale vendor dir when the pin moves.
  version = pvmigrateSrc.version or "unstable-${builtins.substring 0 7 pvmigrateSrc.revision}";

  src = pvmigrateSrc;

  vendorHash = "sha256-BdP/58lUHOS0i/UUowZXAtXVwz7vGDZ/NfhRi9q8iEo=";

  subPackages = [ "cmd" ];
  postInstall = ''
    mv $out/bin/cmd $out/bin/pvmigrate
  '';

  meta = {
    homepage = "https://github.com/replicatedhq/pvmigrate";
    description = "Migrate PersistentVolumeClaims between StorageClasses in Kubernetes.";
    mainProgram = "pvmigrate";
  };
}
