{ pkgs }:
let
  version = "0.18.0";
  srcs = {
    x86_64-linux = pkgs.fetchurl {
      url = "https://github.com/steipete/CodexBar/releases/download/v${version}/CodexBarCLI-v${version}-linux-x86_64.tar.gz";
      hash = "sha256-0hh6bd6733b0c2rq8l4wz7vycjai2nminnzs0hb919ci6lq2cbv2";
    };
    aarch64-linux = pkgs.fetchurl {
      url = "https://github.com/steipete/CodexBar/releases/download/v${version}/CodexBarCLI-v${version}-linux-aarch64.tar.gz";
      hash = "sha256-0avrh558x5qq7spm2s4f740b012f999kx1nc7b7bbsqiv5dwf7v0";
    };
  };
in
pkgs.stdenv.mkDerivation {
  pname = "codexbar";
  inherit version;

  src =
    srcs.${pkgs.stdenv.hostPlatform.system}
      or (throw "Unsupported system: ${pkgs.stdenv.hostPlatform.system}");

  nativeBuildInputs = [ pkgs.autoPatchelfHook ];

  buildInputs = [
    pkgs.curl
    pkgs.libxml2
    pkgs.sqlite
    pkgs.stdenv.cc.cc.lib
  ];

  sourceRoot = ".";

  unpackPhase = ''
    tar xzf $src
  '';

  installPhase = ''
    mkdir -p $out/bin
    install -m 0755 CodexBarCLI $out/bin/CodexBarCLI
    ln -s CodexBarCLI $out/bin/codexbar
  '';

  meta = with pkgs.lib; {
    homepage = "https://github.com/steipete/CodexBar";
    description = "CLI tool showing usage stats for Codex, Claude Code, Gemini, Copilot, and other AI providers";
    license = licenses.mit;
    mainProgram = "codexbar";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
