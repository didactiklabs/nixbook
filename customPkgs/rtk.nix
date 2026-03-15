{ pkgs }:

pkgs.buildRustPackage rec {
  pname = "rtk";
  version = "0.29.0";

  src = pkgs.fetchFromGitHub {
    owner = "rtk-ai";
    repo = "rtk";
    rev = "v${version}";
    sha256 = "sha256-b5mZNVBZGdDn8zt8YjMVKb9xF8xyPSbN+gPj2eV+4Yk=";
  };

  cargoHash = "sha256-Zb8W4vOkS7tZNrVUXyLfXZYwGKq2N9PmXvJy6nG8xXo=";

  # RTK is a single binary with no features to configure
  meta = {
    homepage = "https://github.com/rtk-ai/rtk";
    description = "CLI proxy that reduces LLM token consumption by 60-90% on common dev commands";
    longDescription = ''
      RTK (Rust Token Killer) is a high-performance CLI proxy that filters and
      compresses command outputs before they reach your LLM context. It reduces
      token consumption by 60-90% on common development commands with zero
      dependencies and <10ms overhead.
    '';
    license = pkgs.lib.licenses.mit;
    mainProgram = "rtk";
    platforms = pkgs.lib.platforms.unix;
  };
}
