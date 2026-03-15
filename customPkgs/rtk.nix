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

  # Note: RTK only depends on crates.io packages, no git dependencies
  # When building fails due to cargoHash, nix will report the correct hash
  # Copy it below and remove the comment
  cargoHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # TODO: Replace with actual hash from build output

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
