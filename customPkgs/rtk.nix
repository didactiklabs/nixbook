{ pkgs }:

pkgs.rustPlatform.buildRustPackage rec {
  pname = "rtk";
  version = "0.29.0";

  src = pkgs.fetchFromGitHub {
    owner = "rtk-ai";
    repo = "rtk";
    rev = "v${version}";
    sha256 = "sha256-QGHCa8rO4YBFXdrz78FhWKFxY7DmRxCXM8iYQv4yTYE=";
  };

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
    longDescription = ''
      RTK (Rust Token Killer) is a high-performance CLI proxy that filters and
      compresses command outputs before they reach your LLM context. It reduces
      token consumption by 60-90% on common development commands with zero
      dependencies and <10ms overhead.
    '';
    license = licenses.mit;
    mainProgram = "rtk";
    platforms = platforms.unix;
  };
}
