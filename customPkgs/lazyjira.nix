{ pkgs }:
let
  sources = import ../npins;
  lazyjiraSrc = sources.lazyjira;
in
pkgs.buildGoModule {
  pname = "lazyjira";
  version = "nix";

  src = lazyjiraSrc;

  vendorHash = "sha256-+Vepf1VohkjtL7JvmuZv8qZ5FiLarII+bx4jK6C2bBU=";

  subPackages = [ "cmd/lazyjira" ];

  meta = {
    homepage = "https://github.com/textfuel/lazyjira";
    description = "Terminal UI for Jira. Like lazygit but for Jira.";
    license = "MIT";
    mainProgram = "lazyjira";
  };
}
