{ pkgs }:
# Cerbos — stateless authorization PDP (https://github.com/cerbos/cerbos).
# Uses the upstream prebuilt Linux x86_64 release tarball (the way the docs
# recommend installing the binary) instead of building the large Go project
# from source.
let
  sources = import ../npins;
  # The release tarball (URL + hash) is tracked by npins as a `url` pin in
  # npins/sources.json. To bump the version, update that pin's URL (npins will
  # refetch and record the new hash) — nothing here is hardcoded.
  pin = sources.cerbos;
  pname = "cerbos";
  # Extract the version from the pinned asset URL (.../download/vX.Y.Z/...).
  version = pkgs.lib.removePrefix "v" (
    builtins.head (builtins.match ".*/download/([^/]+)/.*" pin.url)
  );
  src = pkgs.fetchurl { inherit (pin) url hash; };
in
pkgs.stdenv.mkDerivation {
  inherit pname version src;

  sourceRoot = ".";

  nativeBuildInputs = [ pkgs.autoPatchelfHook ];
  buildInputs = [ pkgs.stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall
    install -m 755 -D cerbos $out/bin/cerbos
    install -m 755 -D cerbosctl $out/bin/cerbosctl
    install -m 444 -D LICENSE $out/share/doc/${pname}/LICENSE
    runHook postInstall
  '';

  meta = with pkgs.lib; {
    description = "Stateless authorization policy decision point (PDP)";
    homepage = "https://cerbos.dev/";
    license = licenses.asl20;
    mainProgram = pname;
    platforms = [ "x86_64-linux" ];
  };
}
