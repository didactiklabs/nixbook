{ pkgs }:
let
  sources = import ../npins;
  songbirdSrc = sources.songbird;
  inherit (songbirdSrc) version;
in
pkgs.buildGoModule {
  pname = "songbird";
  version = "${version}";

  src = songbirdSrc;

  vendorHash = "sha256-mcbLV7HzDK0APJ+IPEBpHk3CH1Vm4a2Wjts/aElq3dw=";
  ldflags = [
    "-s"
    "-w"
    "-X github.com/Banh-Canh/songbird/cmd.version=${version}"
  ];

  subPackages = [ "." ];

  nativeBuildInputs = [ pkgs.installShellFiles ];
  postInstall = ''
    installShellCompletion --cmd songbird \
      --zsh <($out/bin/songbird completion zsh)
  '';

  meta = {
    mainProgram = "songbird";
  };
}
