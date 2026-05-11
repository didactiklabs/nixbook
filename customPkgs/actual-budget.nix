{ pkgs }:
let
  pname = "actual-budget";
  version = "26.5.2";
  src = pkgs.fetchurl {
    url = "https://github.com/actualbudget/actual/releases/download/v${version}/Actual-linux-x86_64.AppImage";
    hash = "sha256-gFJWmfZKCdbo+yohRMNB2EiNKq7RpcQTAFPMI9Z56IY=";
  };
  appimageContents = pkgs.appimageTools.extract { inherit pname version src; };
in
pkgs.appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -m 444 -D ${appimageContents}/actual.desktop $out/share/applications/${pname}.desktop
    install -m 444 -D ${appimageContents}/actual.png $out/share/pixmaps/${pname}.png
    substituteInPlace $out/share/applications/${pname}.desktop \
      --replace-fail 'Exec=AppRun' 'Exec=${pname}'
  '';

  meta = {
    description = "A local-first personal finance app";
    homepage = "https://actualbudget.org";
    mainProgram = pname;
  };
}
