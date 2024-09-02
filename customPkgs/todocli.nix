{ pkgs }:
let
  sources = import ../npins;
  todocliSrc = sources.todocli;
in
pkgs.buildGoModule {
  pname = "todocli";
  version = "nix";

  src = todocliSrc;

  vendorHash = "sha256-6M1d2JAj9yCN9hIhE8QL+GXH3QdNhPCdm1Fa/j5X1lE=";

  subPackages = [ "cmd/todo" ];

  meta = {
    homepage = "https://github.com/HxX2/todocli";
    description = "Todo CLI to manage your to do list in a neat way";
    mainProgram = "todocli";
  };
}
