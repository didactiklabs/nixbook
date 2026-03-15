{ pkgs }:
let
  sources = import ../npins;
  rtkSrc = sources.rtk;
in
pkgs.rustPlatform.buildRustPackage rec {
  pname = "rtk";
  version = "${rtkSrc.version}";

  src = rtkSrc;

  # Use importCargoLock for faster builds - avoids lengthy cargo hash verification
  # Cargo.lock is fetched from the source, allowing deterministic reproducible builds
  cargoDeps = pkgs.rustPlatform.importCargoLock {
    lockFile = "${src}/Cargo.lock";
  };

  # Skip tests - they fail in sandbox due to permission denied on tracker creation
  # The tracking tests try to write to ~/.local/share/rtk/history.db which isn't
  # available in the isolated build environment
  doCheck = false;

  meta = with pkgs.lib; {
    homepage = "https://github.com/rtk-ai/rtk";
    description = "CLI proxy that reduces LLM token consumption by 60-90% on common dev commands";
    mainProgram = "rtk";
    platforms = platforms.unix;
  };
}
